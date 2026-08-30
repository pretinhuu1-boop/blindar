#!/usr/bin/env bash
# check-chaos-run — resiliência EXECUTADA: congela a dependência e mede.
#
# O blindar já tinha agents/chaos-engineering.md desde a v0.2x. Ele prescreve
# GameDay, exige staging e "6+ meses de produção", e nunca derrubou nada: era
# um playbook que um subagente lia e reportava. Ao lado dele,
# check-fallback-resilience e check-process-resilience procuram no repositório o
# CÓDIGO do breaker — provam que existe, não que segura.
#
# Este check fecha essa distância. Ele congela o container da dependência com
# `docker pause` e mede três coisas que nenhuma leitura de código responde:
#
#   1. LATÊNCIA DA FALHA — quanto o health pendura com o banco congelado.
#      `docker pause` não mata: o socket fica aberto e ninguém recebe RST. É o
#      modo de falha que mais dói, porque matar o container devolve "connection
#      refused" na hora (que o código trata) e congelar devolve silêncio (que o
#      código costuma esperar para sempre).
#   2. BLAST RADIUS — se a rota que NÃO depende da dependência continua viva.
#      Separa "degradou" de "caiu".
#   3. RECUPERAÇÃO — se volta sozinho ao descongelar, e em quanto tempo.
#
# Uso:
#   bash check-chaos-run.sh --url http://localhost:3000 [--health /healthz]
#                           [--service postgres]
#
# Limiares (env):
#   BLINDAR_CHAOS_MAX_HANG_MS   trava máxima aceitável   (default 5000)
#   BLINDAR_CHAOS_MAX_RECOVER_S recuperação máxima       (default 60)
#
# Exit: 0 = mediu e passou | 1 = mediu e reprovou | 0 com skipped = não exercitou

BLINDAR_AGENT="check-chaos-run"
STARTED_AT=$(date -u +%s)
source "$(dirname "$0")/_lib.sh"
source "$(dirname "$0")/_dyn.sh"
declare_dynamic

log_section "Chaos EXECUTADO (congela a dependência e mede)"

dyn_parse_args "$@"

MAX_HANG_MS="${BLINDAR_CHAOS_MAX_HANG_MS:-5000}"
MAX_RECOVER_S="${BLINDAR_CHAOS_MAX_RECOVER_S:-60}"
case "$MAX_HANG_MS" in ''|*[!0-9]*) MAX_HANG_MS=5000 ;; esac
case "$MAX_RECOVER_S" in ''|*[!0-9]*) MAX_RECOVER_S=60 ;; esac

dyn_need_curl   || { emit_result "$BLINDAR_AGENT" "skipped" 0; exit 0; }
dyn_need_target || { emit_result "$BLINDAR_AGENT" "skipped" 0; exit 0; }
dyn_need_docker || { emit_result "$BLINDAR_AGENT" "skipped" 0; exit 0; }

HEALTH_URL="${DYN_TARGET%/}${DYN_HEALTH}"
ROOT_URL="${DYN_TARGET%/}/"

# ─── Pré-condição: o alvo precisa estar SAUDÁVEL antes ───
# Medir degradação a partir de um sistema que já estava quebrado não mede nada.
BASE=$(dyn_probe "$HEALTH_URL" 10)
BASE_CODE=$(echo "$BASE" | awk '{print $1}')
BASE_MS=$(echo "$BASE" | awk '{print $2}')
case "$BASE_CODE" in
  2*|3*) : ;;
  *)
    not_exercised "alvo nao estava saudavel antes do experimento (health=$BASE_CODE) — degradacao a partir de sistema quebrado nao mede nada"
    log_warn "Health devolveu $BASE_CODE ANTES de congelar nada — abortando o experimento."
    emit_result "$BLINDAR_AGENT" "skipped" 0
    exit 0
    ;;
esac
log_info "Baseline: health=$BASE_CODE em ${BASE_MS}ms"

# ─── Escolhe a dependência a congelar ───
# dyn_pick_dependency só devolve container AMARRADO ao alvo (mesmo projeto
# compose de quem publica a porta), ou o que o operador passou em --service.
# Casar por padrão de nome na máquina inteira congelaria container de outro
# projeto — aconteceu ao exercitar este próprio check.
DEP_PATTERN="postgres|postgis|mysql|mariadb|mongo|redis|valkey|rabbit|kafka|elastic|meilisearch"
TARGET_PORT=$(dyn_port_of_target "$DYN_TARGET")
if ! dyn_pick_dependency "$DEP_PATTERN" "$TARGET_PORT"; then
  log_warn "Nenhuma dependência segura de congelar: ${BLINDAR_NOT_EXERCISED_REASON}"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi
DEP="$DYN_DEP"
log_info "Dependência escolhida: $DEP"

# ─── Experimento ───
if ! dyn_freeze "$DEP"; then
  not_exercised "docker pause falhou em '$DEP' — o experimento nao chegou a rodar"
  log_warn "Não consegui congelar $DEP."
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi
log_info "$DEP CONGELADO — medindo o sistema sob falha..."

# A partir daqui o sistema FOI tocado. Mesmo que tudo dê errado adiante, o
# exercício aconteceu e o result não pode dizer "não medi".
mark_exercised

# 1. Latência da falha. Teto de 30s: se pendurar mais que isso, o dado que
#    interessa (pendura indefinidamente) já está capturado.
FAIL_PROBE=$(dyn_probe "$HEALTH_URL" 30)
FAIL_CODE=$(echo "$FAIL_PROBE" | awk '{print $1}')
FAIL_MS=$(echo "$FAIL_PROBE" | awk '{print $2}')
log_info "Sob falha: health=$FAIL_CODE em ${FAIL_MS}ms (baseline ${BASE_MS}ms)"

# 2. Blast radius: a rota que não depende da dependência continua viva?
BLAST_PROBE=$(dyn_probe "$ROOT_URL" 10)
BLAST_CODE=$(echo "$BLAST_PROBE" | awk '{print $1}')
BLAST_MS=$(echo "$BLAST_PROBE" | awk '{print $2}')
log_info "Rota independente ($ROOT_URL): $BLAST_CODE em ${BLAST_MS}ms"

# 3. Recuperação
dyn_unfreeze "$DEP"
log_info "$DEP descongelado — medindo recuperação (teto ${MAX_RECOVER_S}s)..."
RECOVER_MS=$(dyn_wait_recovery "$HEALTH_URL" "$MAX_RECOVER_S")
trap - EXIT INT TERM

FAIL=0

# ─── Vereditos ───
if [ "$FAIL_MS" -ge 30000 ]; then
  add_finding "crit" "Com '$DEP' congelado, ${DYN_HEALTH} pendurou ${FAIL_MS}ms sem responder (teto do experimento). Socket aberto sem RST faz o cliente esperar para sempre: sem timeout de conexão, o pool esgota e a app inteira para por uma dependência que nem caiu" "" ""
  FAIL=1
elif [ "$FAIL_MS" -gt "$MAX_HANG_MS" ]; then
  add_finding "high" "Com '$DEP' congelado, ${DYN_HEALTH} levou ${FAIL_MS}ms (limite ${MAX_HANG_MS}ms, baseline ${BASE_MS}ms). O código de breaker existe mas não corta a tempo — quem chama desiste antes dele" "" ""
  FAIL=1
else
  log_pass "Falha detectada em ${FAIL_MS}ms (limite ${MAX_HANG_MS}ms)"
fi

case "$BLAST_CODE" in
  000|5*)
    add_finding "high" "Com '$DEP' congelado, a rota independente $ROOT_URL também caiu ($BLAST_CODE). Blast radius total: uma dependência degradada derruba o que não depende dela — o fluxo que poderia continuar servindo para junto" "" ""
    FAIL=1
    ;;
  *) log_pass "Blast radius contido: rota independente respondeu $BLAST_CODE" ;;
esac

if [ "$RECOVER_MS" = "-1" ]; then
  add_finding "crit" "Após descongelar '$DEP', o sistema NÃO voltou em ${MAX_RECOVER_S}s. Recuperação manual obrigatória: toda queda de dependência vira incidente com gente acordada, mesmo quando a dependência já voltou sozinha" "" ""
  FAIL=1
else
  log_pass "Recuperou sozinho em ${RECOVER_MS}ms"
fi

# Registro do experimento: evidência é o que separa gate de opinião.
mkdir -p "$BLINDAR_DIR" 2>/dev/null || true
cat > "$BLINDAR_DIR/chaos-run.json" <<EOF
{
  "schema": "blindar/chaos-run@v1",
  "ran_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "target": "$HEALTH_URL",
  "frozen_container": "$DEP",
  "baseline_ms": $BASE_MS,
  "under_failure_ms": $FAIL_MS,
  "under_failure_code": "$FAIL_CODE",
  "blast_radius_code": "$BLAST_CODE",
  "recovery_ms": $RECOVER_MS,
  "limits": { "max_hang_ms": $MAX_HANG_MS, "max_recover_s": $MAX_RECOVER_S }
}
EOF

if [ "$FAIL" -eq 1 ]; then
  emit_result "$BLINDAR_AGENT" "failed" 1
  exit 1
fi
emit_result "$BLINDAR_AGENT" "passed" 0
exit 0
