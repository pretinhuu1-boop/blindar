#!/usr/bin/env bash
# check-redteam-origin — ataca de OUTRA origem de rede, não do próprio host.
#
# scripts/pentest-active.sh e scripts/attack-recon.sh já mandam payload real —
# do mesmo host onde o blindar roda. Isso esconde toda uma classe de defeito:
# o que separa "dentro" de "fora" só se manifesta quando a requisição chega de
# outro endereço.
#
# Este check sobe um container efêmero DENTRO da rede do alvo e compara três
# origens:
#
#   1. HOST      — a porta publicada, como o blindar sempre bateu
#   2. REDE      — de dentro da rede docker, como um vizinho de container
#   3. SPOOF     — com X-Forwarded-For forjado, como quem tenta virar 127.0.0.1
#
# Divergência entre 1 e 2 é fronteira mal desenhada: rota que o proxy filtra
# mas que o vizinho alcança direto. Ganho de acesso em 3 é confiança cega em
# header de cliente — o furo que só aparece batendo de fora.
#
# Tráfego real exige papel assinado: mesma convenção do pentest ativo
# (.accept-authorization com 'authorized: yes' + 'scope:').
#
# Uso: bash check-redteam-origin.sh --url http://localhost:3000

BLINDAR_AGENT="check-redteam-origin"
STARTED_AT=$(date -u +%s)
source "$(dirname "$0")/_lib.sh"
source "$(dirname "$0")/_dyn.sh"
declare_dynamic

log_section "Red team de ORIGEM (rede interna x porta publicada x XFF forjado)"

dyn_parse_args "$@"

dyn_need_curl   || { emit_result "$BLINDAR_AGENT" "skipped" 0; exit 0; }
dyn_need_target || { emit_result "$BLINDAR_AGENT" "skipped" 0; exit 0; }

BASE="${DYN_TARGET%/}"
HOST=$(printf '%s' "$BASE" | sed -E 's#https?://##; s#/.*##; s#:.*##')

dyn_need_authorization "$HOST" || { emit_result "$BLINDAR_AGENT" "skipped" 0; exit 2; }
dyn_need_docker || { emit_result "$BLINDAR_AGENT" "skipped" 0; exit 0; }

# ─── Descobre a rede do alvo ───
APP=$(dyn_find_container "${DYN_SERVICE:-app|api|web|backend|server|next|node|django|fastapi}")
if [ -z "$APP" ]; then
  not_exercised "nenhum container de aplicacao encontrado — sem rede alvo nao ha origem externa para usar"
  log_warn "Nenhum container de app encontrado. Aponte com --service <padrão>."
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi
NET=$(dyn_net_of_container "$APP")
if [ -z "$NET" ]; then
  not_exercised "container '$APP' sem rede docker identificavel"
  log_warn "Não identifiquei a rede de $APP."
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi
log_info "Alvo: $APP na rede $NET"

# Endereço interno: dentro da rede o alvo é o NOME do container, não localhost.
INTERNAL_PORT="${BLINDAR_REDTEAM_PORT:-$(printf '%s' "$BASE" | sed -nE 's#.*:([0-9]+).*#\1#p')}"
[ -z "$INTERNAL_PORT" ] && INTERNAL_PORT=80
INTERNAL_BASE="http://${APP}:${INTERNAL_PORT}"

# Sanidade: se o container efêmero não alcança o alvo, não há comparação a
# fazer — e reportar "nenhuma divergência" seria dizer que está tudo bem sobre
# um experimento que não aconteceu.
SANITY=$(dyn_curl_from_network "$NET" "${INTERNAL_BASE}${DYN_HEALTH}")
SANITY_CODE=$(dyn_code_of "$SANITY")
if [ "$SANITY_CODE" = "000" ]; then
  not_exercised "container efemero nao alcancou ${INTERNAL_BASE} — comparacao entre origens nao aconteceu"
  log_warn "Da rede $NET não alcancei $INTERNAL_BASE (ajuste BLINDAR_REDTEAM_PORT)."
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi
mark_exercised
log_info "Origem externa operante: rede $NET alcança $INTERNAL_BASE ($SANITY_CODE)"

PATHS="${BLINDAR_REDTEAM_PATHS:-/ ${DYN_HEALTH} /metrics /admin /actuator/health /debug /internal /.env}"
FAIL=0
ROWS=""

for p in $PATHS; do
  HOST_R=$(dyn_probe "${BASE}${p}" 8); HOST_C=$(echo "$HOST_R" | awk '{print $1}')
  NET_R=$(dyn_curl_from_network "$NET" "${INTERNAL_BASE}${p}"); NET_C=$(dyn_code_of "$NET_R")
  ROWS="${ROWS}{\"path\":\"$p\",\"from_host\":\"$HOST_C\",\"from_network\":\"$NET_C\"},"
  log_info "$p  host=$HOST_C  rede=$NET_C"

  # Rota que a fronteira bloqueia e o vizinho alcança.
  case "$HOST_C:$NET_C" in
    40[0-9]:2*|000:2*)
      add_finding "high" "A rota '$p' é bloqueada na porta publicada ($HOST_C) mas responde 200 de dentro da rede. A proteção está no proxy, não na aplicação: qualquer container vizinho comprometido alcança o endpoint direto" "" ""
      FAIL=1 ;;
  esac

  # Superfície que não deveria existir em nenhuma origem.
  case "$p:$NET_C" in
    /.env:2*)
      add_finding "crit" "'$p' responde 200 de dentro da rede — arquivo de ambiente servido pela aplicação" "" ""
      FAIL=1 ;;
    /metrics:2*|/actuator/health:2*|/debug:2*|/internal:2*)
      add_finding "med" "'$p' responde $NET_C de dentro da rede sem autenticação — superfície interna exposta a vizinhos de container" "" ""
      ;;
  esac
done

# ─── X-Forwarded-For forjado ───
# Se uma rota nega da rede e aceita com XFF=127.0.0.1, a app confia em header
# de cliente para decidir quem é interno. Qualquer um manda esse header.
for p in ${BLINDAR_REDTEAM_TRUST_PATHS:-/admin /metrics /internal /debug}; do
  PLAIN=$(dyn_curl_from_network "$NET" "${INTERNAL_BASE}${p}")
  PLAIN_C=$(dyn_code_of "$PLAIN")
  SPOOF=$(dyn_curl_from_network "$NET" "${INTERNAL_BASE}${p}" -H "X-Forwarded-For: 127.0.0.1")
  SPOOF_C=$(dyn_code_of "$SPOOF")
  [ "$PLAIN_C" = "$SPOOF_C" ] && continue
  ROWS="${ROWS}{\"path\":\"$p\",\"plain\":\"$PLAIN_C\",\"xff_spoof\":\"$SPOOF_C\"},"
  case "$PLAIN_C:$SPOOF_C" in
    40[13]:2*)
      add_finding "crit" "'$p' nega acesso ($PLAIN_C) mas LIBERA ($SPOOF_C) com 'X-Forwarded-For: 127.0.0.1'. A aplicação decide quem é interno lendo um header que o cliente escolhe — a autorização é forjável por qualquer um que saiba digitar o header" "" ""
      FAIL=1 ;;
    *)
      add_finding "med" "'$p' responde diferente com XFF forjado ($PLAIN_C → $SPOOF_C): há decisão baseada em header de cliente, ainda que não conceda acesso direto" "" ""
      ;;
  esac
done

mkdir -p "$BLINDAR_DIR" 2>/dev/null || true
cat > "$BLINDAR_DIR/redteam-origin.json" <<EOF
{
  "schema": "blindar/redteam-origin@v1",
  "ran_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "published_base": "$BASE",
  "internal_base": "$INTERNAL_BASE",
  "network": "$NET",
  "observations": [${ROWS%,}]
}
EOF

if [ "$FAIL" -eq 1 ]; then
  emit_result "$BLINDAR_AGENT" "failed" 1
  exit 1
fi
emit_result "$BLINDAR_AGENT" "passed" 0
exit 0
