#!/usr/bin/env bash
# Materializa: worker-jobs — worker configurado sem jobs registrados (functions=[]).
# Bug real: WorkerSettings.functions=[] → worker sobe mas não processa nada.
BLINDAR_AGENT="check-worker-jobs"
source "$(dirname "$0")/_lib.sh"
log_section "Check: worker-jobs (worker sem jobs registrados)"

if ! command -v rg >/dev/null 2>&1; then emit_result "$BLINDAR_AGENT" "skipped" 0; exit 0; fi
IGNORE=(-g '!node_modules' -g '!dist' -g '!.git' -g '!**/*.test.*')
load_intelligence_globs "$BLINDAR_AGENT"
FAIL=0

# functions/tasks/jobs = [] vazio (arq/celery-ish/custom worker)
EMPTY_FN=$(rg -c "(functions|tasks|jobs|processors|handlers)\s*[:=]\s*\[\s*\]" --type py --type ts --type js "${IGNORE[@]}" "${INTEL_GLOBS[@]}" 2>/dev/null | wc -l)
if [ "$EMPTY_FN" -gt 0 ]; then
  add_finding "high" "Worker com lista de jobs vazia (functions/tasks=[]) — o worker sobe mas não processa nada. Registre os handlers" "" ""
  FAIL=1
fi

# BullMQ Worker sem processor (segundo arg ausente): new Worker('q') sem função
BULL_NOPROC=$(rg -n "new Worker\(\s*['\"][^'\"]+['\"]\s*\)" --type ts --type js "${IGNORE[@]}" "${INTEL_GLOBS[@]}" 2>/dev/null | wc -l)
if [ "$BULL_NOPROC" -gt 0 ]; then
  add_finding "high" "BullMQ Worker instanciado sem função processadora — jobs entram na fila e nunca rodam" "" ""
  FAIL=1
fi

if [ "$FAIL" -eq 1 ]; then emit_result "$BLINDAR_AGENT" "failed" 1; exit 1; fi
emit_result "$BLINDAR_AGENT" "passed" 0
