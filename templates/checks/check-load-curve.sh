#!/usr/bin/env bash
# check-load-curve — a CURVA de escala, não um ponto contra SLO.
#
# scripts/load-test.sh (v0.43) dispara N requisições numa concorrência só e
# reprova se erro% ou p95 estourarem o SLO. Isso responde "passou ou não passou
# neste ponto", e é uma pergunta diferente de "onde começa a degradar".
#
# Um sistema pode passar folgado em 20 concorrentes e saturar em 60. O gate de
# um ponto diz VERDE. A curva diz onde está o joelho — e joelho conhecido é a
# diferença entre planejar capacidade e descobrir o limite num pico real.
#
# Este check sobe uma rampa e mede p50/p95/p99 + erro% por nível. O veredito é
# sobre o JOELHO: o primeiro nível em que o p95 estoura o fator de degradação
# em relação ao nível base, ou em que o erro% passa do SLO.
#
# Uso:
#   bash check-load-curve.sh --url http://localhost:3000/healthz
#
# Parâmetros (env):
#   BLINDAR_LOAD_LEVELS      níveis de concorrência   (default "5 10 25 50 100")
#   BLINDAR_LOAD_REQS_FACTOR requisições = nivel * F  (default 4)
#   BLINDAR_LOAD_KNEE_MIN    joelho mínimo aceitável  (default 50)
#   BLINDAR_LOAD_DEGRADE_X   fator de degradação p95  (default 4)
#   BLINDAR_LOAD_SLO_ERR_PCT erro% máximo por nível   (default 1)

BLINDAR_AGENT="check-load-curve"
STARTED_AT=$(date -u +%s)
source "$(dirname "$0")/_lib.sh"
source "$(dirname "$0")/_dyn.sh"
declare_dynamic

log_section "Curva de escala (rampa, joelho de saturação)"

dyn_parse_args "$@"

LEVELS="${BLINDAR_LOAD_LEVELS:-5 10 25 50 100}"
FACTOR="${BLINDAR_LOAD_REQS_FACTOR:-4}"
KNEE_MIN="${BLINDAR_LOAD_KNEE_MIN:-50}"
DEGRADE_X="${BLINDAR_LOAD_DEGRADE_X:-4}"
SLO_ERR="${BLINDAR_LOAD_SLO_ERR_PCT:-1}"
case "$FACTOR"    in ''|*[!0-9]*)   FACTOR=4 ;; esac
case "$KNEE_MIN"  in ''|*[!0-9]*)   KNEE_MIN=50 ;; esac
case "$DEGRADE_X" in ''|*[!0-9]*)   DEGRADE_X=4 ;; esac
case "$SLO_ERR"   in ''|*[!0-9.]*)  SLO_ERR=1 ;; esac
# Níveis vêm do operador e viram aritmética: filtra qualquer coisa não-numérica
# antes de usar, em vez de deixar o awk receber texto e devolver zero calado.
CLEAN_LEVELS=""
for l in $LEVELS; do
  case "$l" in ''|*[!0-9]*) log_warn "nível '$l' ignorado (não é inteiro)" ;; *) CLEAN_LEVELS="$CLEAN_LEVELS $l" ;; esac
done
LEVELS=$(echo "$CLEAN_LEVELS" | xargs)
[ -z "$LEVELS" ] && LEVELS="5 10 25 50 100"

dyn_need_curl   || { emit_result "$BLINDAR_AGENT" "skipped" 0; exit 0; }
dyn_need_target || { emit_result "$BLINDAR_AGENT" "skipped" 0; exit 0; }

URL="$DYN_TARGET"
case "$URL" in http://*|https://*) : ;; *) URL="http://$URL" ;; esac

# Pré-condição: um alvo já quebrado transforma a curva em ruído.
PRE=$(dyn_probe "$URL" 10)
PRE_CODE=$(echo "$PRE" | awk '{print $1}')
case "$PRE_CODE" in
  2*|3*) : ;;
  *)
    not_exercised "alvo respondeu $PRE_CODE antes da rampa — curva sobre sistema quebrado nao mede escala"
    log_warn "Alvo devolveu $PRE_CODE antes de qualquer carga — abortando."
    emit_result "$BLINDAR_AGENT" "skipped" 0
    exit 0
    ;;
esac

WORK=$(mktemp -d)
CURVE_ROWS=""
BASE_P95=""
KNEE=""
KNEE_WHY=""
FAIL=0

for level in $LEVELS; do
  reqs=$((level * FACTOR))
  samples="$WORK/l$level.txt"
  : > "$samples"
  errs="$WORK/e$level.txt"
  : > "$errs"

  # Concorrência real: `level` requisições em voo ao mesmo tempo, repetido até
  # fechar `reqs`. Sem xargs -P para não depender do flag em toda plataforma.
  sent=0
  while [ "$sent" -lt "$reqs" ]; do
    batch=0
    while [ "$batch" -lt "$level" ] && [ "$sent" -lt "$reqs" ]; do
      (
        r=$(dyn_probe "$URL" 15)
        c=$(echo "$r" | awk '{print $1}')
        m=$(echo "$r" | awk '{print $2}')
        echo "$m" >> "$samples"
        case "$c" in 2*|3*) ;; *) echo "$c" >> "$errs" ;; esac
      ) &
      batch=$((batch + 1)); sent=$((sent + 1))
    done
    wait
  done

  read -r p50 p95 p99 max n <<EOF
$(dyn_percentiles < "$samples")
EOF
  nerr=$(wc -l < "$errs" | tr -d ' ')
  [ -z "$nerr" ] && nerr=0

  if [ "$n" -eq 0 ]; then
    # Nível inteiro sem amostra: não é "0ms, excelente" — é ausência de medição.
    log_warn "nível $level: nenhuma amostra coletada — nível descartado da curva"
    CURVE_ROWS="${CURVE_ROWS}{\"level\":$level,\"measured\":false},"
    continue
  fi

  # Só o primeiro nível COM medição vira base — se o nível 1 falhar em coletar,
  # a base não pode virar zero, senão qualquer p95 vira "degradação infinita".
  [ -z "$BASE_P95" ] && BASE_P95="$p95"
  errpct=$(awk -v e="$nerr" -v t="$n" 'BEGIN{printf "%.2f", (t>0 ? e*100/t : 0)}')

  log_info "conc=$level  n=$n  p50=${p50}ms p95=${p95}ms p99=${p99}ms max=${max}ms  erro=${errpct}%"
  CURVE_ROWS="${CURVE_ROWS}{\"level\":$level,\"measured\":true,\"n\":$n,\"p50\":$p50,\"p95\":$p95,\"p99\":$p99,\"max\":$max,\"error_pct\":$errpct},"

  if [ -z "$KNEE" ]; then
    if awk -v e="$errpct" -v s="$SLO_ERR" 'BEGIN{exit !(e>s)}'; then
      KNEE="$level"; KNEE_WHY="erro ${errpct}% acima do SLO ${SLO_ERR}%"
    elif [ "${BASE_P95:-0}" -gt 0 ] && [ "$p95" -gt $((BASE_P95 * DEGRADE_X)) ]; then
      KNEE="$level"; KNEE_WHY="p95 ${p95}ms = ${DEGRADE_X}x+ do p95 base (${BASE_P95}ms)"
    fi
  fi
done

rm -rf "$WORK"

# Só chega aqui com pelo menos um nível medido; senão a rampa inteira foi vazia.
if [ -z "$BASE_P95" ]; then
  not_exercised "nenhum nivel da rampa produziu amostra — nada foi medido"
  log_warn "A rampa inteira ficou sem amostra."
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi
mark_exercised

TOP=$(echo "$LEVELS" | awk '{print $NF}')

if [ -n "$KNEE" ]; then
  if [ "$KNEE" -lt "$KNEE_MIN" ]; then
    add_finding "high" "Joelho de saturação em ${KNEE} concorrentes (${KNEE_WHY}), abaixo do mínimo aceitável de ${KNEE_MIN}. O sistema degrada antes do volume-alvo: o gate de um ponto só teria dito 'dentro do SLO' e escondido onde a curva vira" "" ""
    FAIL=1
  else
    log_pass "Joelho em ${KNEE} concorrentes (${KNEE_WHY}) — acima do mínimo ${KNEE_MIN}"
  fi
else
  log_pass "Sem joelho até ${TOP} concorrentes (teto da rampa)"
  if [ "$TOP" -lt "$KNEE_MIN" ]; then
    add_finding "med" "A rampa parou em ${TOP} concorrentes, abaixo do mínimo de ${KNEE_MIN} — não há joelho porque não se testou até lá. Ausência de joelho medido não é ausência de joelho" "" ""
  fi
fi

mkdir -p "$BLINDAR_DIR" 2>/dev/null || true
cat > "$BLINDAR_DIR/load-curve.json" <<EOF
{
  "schema": "blindar/load-curve@v1",
  "ran_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "target": "$URL",
  "levels": [${CURVE_ROWS%,}],
  "baseline_p95_ms": $BASE_P95,
  "knee_level": ${KNEE:-null},
  "knee_reason": "${KNEE_WHY:-nenhum joelho ate o teto da rampa}",
  "limits": { "knee_min": $KNEE_MIN, "degrade_x": $DEGRADE_X, "slo_error_pct": $SLO_ERR }
}
EOF
log_info "Curva: $BLINDAR_DIR/load-curve.json"

if [ "$FAIL" -eq 1 ]; then
  emit_result "$BLINDAR_AGENT" "failed" 1
  exit 1
fi
emit_result "$BLINDAR_AGENT" "passed" 0
exit 0
