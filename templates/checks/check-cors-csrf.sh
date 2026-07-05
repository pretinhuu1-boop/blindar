#!/usr/bin/env bash
# Materializa: cors-csrf (CORS amplo + CSRF ausente)
BLINDAR_AGENT="check-cors-csrf"
source "$(dirname "$0")/_lib.sh"
log_section "Check: CORS + CSRF"

if ! command -v rg >/dev/null 2>&1; then emit_result "$BLINDAR_AGENT" "skipped" 0; exit 0; fi

IGNORE=(-g '!node_modules' -g '!dist' -g '!**/*.test.*')
load_intelligence_globs "$BLINDAR_AGENT"
FAIL=0

# 1. CORS origin: * (CRIT)
WILD=$(rg -c "(origin:\s*['\"]?\*|Access-Control-Allow-Origin.*\*)" --type ts --type js "${IGNORE[@]}" "${INTEL_GLOBS[@]}" 2>/dev/null | wc -l || echo 0)
if [ "$WILD" -gt 0 ]; then
  add_finding "crit" "$WILD CORS com origin: '*' — vulnerável a CSRF cross-origin" "" ""
  FAIL=1
fi

# 2. credentials: true + origin reflect (CRIT)
REFLECT=$(rg -n "credentials:\s*true" --type ts -A 2 "${IGNORE[@]}" "${INTEL_GLOBS[@]}" 2>/dev/null | grep -E "origin:.*req\.headers|callback\(null,\s*origin" | wc -l || echo 0)
if [ "$REFLECT" -gt 0 ]; then
  add_finding "crit" "$REFLECT CORS reflect com credentials:true — equivale a sem CORS" "" ""
  FAIL=1
fi

# 3. CSRF middleware ausente em form POST
HAS_CSRF=$(rg -c "(csurf|csrf-csrf|next-csrf|csrfToken)" --type ts --type js "${IGNORE[@]}" "${INTEL_GLOBS[@]}" 2>/dev/null | wc -l || echo 0)
HAS_FORMS=$(rg -c "<form\b" --type ts --type html "${IGNORE[@]}" "${INTEL_GLOBS[@]}" 2>/dev/null | wc -l || echo 0)
if [ "$HAS_FORMS" -gt 0 ] && [ "$HAS_CSRF" -eq 0 ]; then
  add_finding "high" "Forms HTML presentes sem proteção CSRF detectável" "" ""
fi

# 4. SameSite cookie ausente
NO_SAMESITE=$(rg -n "res\.cookie\(|cookies\.set\(" --type ts "${IGNORE[@]}" "${INTEL_GLOBS[@]}" 2>/dev/null | grep -v "sameSite\|SameSite" | wc -l || echo 0)
[ "$NO_SAMESITE" -gt 0 ] && add_finding "high" "$NO_SAMESITE cookie sem SameSite — defesa em profundidade CSRF" "" ""

[ "$FAIL" -eq 1 ] && { emit_result "$BLINDAR_AGENT" "failed" 1; exit 1; }
emit_result "$BLINDAR_AGENT" "passed" 0
