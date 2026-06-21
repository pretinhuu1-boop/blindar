#!/usr/bin/env bash
# Materializa agente: scheduled-jobs
# Cron sem lock, sem dedup, sem watchdog, sem retry com DLQ

BLINDAR_AGENT="check-scheduled-jobs"
source "$(dirname "$0")/_lib.sh"

log_section "Check: scheduled-jobs (Redlock + watchdog + DLQ)"

if ! command -v rg >/dev/null 2>&1; then
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

# Detecta cron/scheduler
HAS_SCHEDULER=0
for pat in "@nestjs/schedule" "node-cron" "bullmq" "agenda"; do
  if grep -qE "\"$pat\":" package.json 2>/dev/null; then
    HAS_SCHEDULER=1
  fi
done

if [ "$HAS_SCHEDULER" -eq 0 ]; then
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

IGNORE=('!node_modules' '!dist' '!build' '!**/*.test.*')
FAIL=0

# 1. Cron sem lock em multi-instance
log_info "Buscando @Cron sem lock distribuído..."
TMP=$(mktemp)
rg -nE "@Cron\(" --type ts "${IGNORE[@]}" -A 8 2>/dev/null | \
  grep -B 2 "async" | grep -v "redlock\|acquire\|lock" > "$TMP" || true
CRON_NO_LOCK=$(grep -c "@Cron" "$TMP" 2>/dev/null || echo 0)
if [ "$CRON_NO_LOCK" -gt 0 ]; then
  add_finding "high" "$CRON_NO_LOCK cron sem Redlock — em multi-instance roda N vezes" "" ""
  log_fail "$CRON_NO_LOCK cron(s) sem lock"
  FAIL=1
fi
rm -f "$TMP"

# 2. BullMQ sem attempts/backoff
log_info "Verificando retry em queue.add..."
TMP=$(mktemp)
rg -nE "queue\.add\(" --type ts "${IGNORE[@]}" -A 5 2>/dev/null | \
  grep -B 5 "}" | grep -v "attempts:\|backoff:" > "$TMP" || true
QUEUE_NO_RETRY=$(grep -c "queue\.add" "$TMP" 2>/dev/null || echo 0)
if [ "$QUEUE_NO_RETRY" -gt 0 ]; then
  add_finding "med" "$QUEUE_NO_RETRY queue.add sem attempts/backoff config" "" ""
fi
rm -f "$TMP"

# 3. Sem watchdog de jobs (alerta quando job para de rodar)
HAS_WATCHDOG=$(rg -lE "(cron_runs|cronRun|watchdog|silent_failure)" --type ts "${IGNORE[@]}" 2>/dev/null | head -1)
if [ -z "$HAS_WATCHDOG" ] && [ "$HAS_SCHEDULER" -eq 1 ]; then
  add_finding "med" "Sem watchdog de jobs — silent failure invisível" "" ""
fi

# 4. Sem DLQ tracking
if grep -qE "bullmq" package.json 2>/dev/null; then
  HAS_DLQ=$(rg -lE "(getFailed|DLQ|dead.letter)" --type ts "${IGNORE[@]}" 2>/dev/null | head -1)
  if [ -z "$HAS_DLQ" ]; then
    add_finding "low" "Sem tracking de DLQ — jobs falhados acumulam invisíveis" "" ""
  fi
fi

# 5. setInterval/setTimeout sem clear (memory leak)
log_info "Buscando timer sem cleanup..."
TMP=$(mktemp)
rg -n "setInterval\(" --type ts "${IGNORE[@]}" -A 3 2>/dev/null | grep -v "clearInterval" > "$TMP" || true
INTERVAL=$(grep -c "setInterval" "$TMP" 2>/dev/null || echo 0)
if [ "$INTERVAL" -gt 3 ]; then
  add_finding "low" "$INTERVAL setInterval sem clearInterval próximo — investigar leak" "" ""
fi
rm -f "$TMP"

if [ "$FAIL" -eq 1 ]; then
  emit_result "$BLINDAR_AGENT" "failed" 1
  exit 1
fi

emit_result "$BLINDAR_AGENT" "passed" 0
exit 0
