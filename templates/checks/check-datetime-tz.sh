#!/usr/bin/env bash
# Materializa: datetime-tz — datetime naive (sem timezone). Bug real: coluna
# last_login_at timezone-naive → comparação/serialização quebra (login 500).
BLINDAR_AGENT="check-datetime-tz"
source "$(dirname "$0")/_lib.sh"
log_section "Check: datetime-tz (datetime naive vs aware)"

if ! command -v rg >/dev/null 2>&1; then emit_result "$BLINDAR_AGENT" "skipped" 0; exit 0; fi
IGNORE=(-g '!node_modules' -g '!dist' -g '!.git' -g '!**/*.test.*')
load_intelligence_globs "$BLINDAR_AGENT"
FAIL=0

# Python: datetime.utcnow() e datetime.now() SEM timezone → naive
NAIVE_NOW=$(rg -c "datetime\.utcnow\(\)" --type py "${IGNORE[@]}" "${INTEL_GLOBS[@]}" 2>/dev/null | wc -l)
if [ "$NAIVE_NOW" -gt 0 ]; then
  add_finding "high" "datetime.utcnow() é NAIVE (sem timezone) — deprecado e quebra comparação/serialização. Use datetime.now(timezone.utc)" "" ""
  FAIL=1
fi

# SQLAlchemy DateTime sem timezone=True
DT_NAIVE=$(rg -c "Column\([^)]*DateTime\b" --type py "${IGNORE[@]}" "${INTEL_GLOBS[@]}" 2>/dev/null | wc -l)
DT_AWARE=$(rg -c "DateTime\(timezone=True\)|DateTime\(timezone = True\)" --type py "${IGNORE[@]}" "${INTEL_GLOBS[@]}" 2>/dev/null | wc -l)
if [ "$DT_NAIVE" -gt 0 ] && [ "$DT_AWARE" -eq 0 ]; then
  add_finding "med" "Coluna DateTime sem timezone=True — no Postgres vira timestamp without time zone (naive). Use DateTime(timezone=True)" "" ""
fi

if [ "$FAIL" -eq 1 ]; then emit_result "$BLINDAR_AGENT" "failed" 1; exit 1; fi
[ "${#FINDINGS[@]}" -gt 0 ] && { emit_result "$BLINDAR_AGENT" "failed" 1; exit 0; }
emit_result "$BLINDAR_AGENT" "passed" 0
