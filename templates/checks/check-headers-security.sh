#!/usr/bin/env bash
# Materializa: headers-security (CSP, HSTS, X-Frame, etc.)
BLINDAR_AGENT="check-headers-security"
source "$(dirname "$0")/_lib.sh"
log_section "Check: HTTP security headers"

if ! command -v rg >/dev/null 2>&1; then emit_result "$BLINDAR_AGENT" "skipped" 0; exit 0; fi

IGNORE=(-g '!node_modules' -g '!dist' -g '!**/*.test.*')
load_intelligence_globs "$BLINDAR_AGENT"
MISSING=()

# Detecta uso de helmet ou config manual
HELMET=$(rg -c "helmet" --type ts --type js "${IGNORE[@]}" "${INTEL_GLOBS[@]}" 2>/dev/null | wc -l || echo 0)
NEXT_HEADERS=$(rg -c "headers\(\)" next.config.* 2>/dev/null | wc -l || echo 0)

if [ "$HELMET" -eq 0 ] && [ "$NEXT_HEADERS" -eq 0 ]; then
  # Verifica cada header individualmente
  for h in "Content-Security-Policy" "Strict-Transport-Security" "X-Frame-Options" "X-Content-Type-Options" "Referrer-Policy" "Permissions-Policy"; do
    PRESENT=$(rg -c "$h" --type ts --type js --type json "${IGNORE[@]}" "${INTEL_GLOBS[@]}" 2>/dev/null | wc -l || echo 0)
    [ "$PRESENT" -eq 0 ] && MISSING+=("$h")
  done

  if [ "${#MISSING[@]}" -gt 0 ]; then
    add_finding "high" "Headers ausentes: ${MISSING[*]} — usar helmet ou config manual" "" ""
    emit_result "$BLINDAR_AGENT" "failed" 1
    exit 1
  fi
fi

# CSP com 'unsafe-inline' (high)
UNSAFE_INLINE=$(rg -c "unsafe-inline" --type ts --type js --type json "${IGNORE[@]}" "${INTEL_GLOBS[@]}" 2>/dev/null | wc -l || echo 0)
[ "$UNSAFE_INLINE" -gt 0 ] && add_finding "high" "$UNSAFE_INLINE CSP com 'unsafe-inline' — usar nonce/hash" "" ""

# CSP com 'unsafe-eval'
UNSAFE_EVAL=$(rg -c "unsafe-eval" --type ts --type js --type json "${IGNORE[@]}" "${INTEL_GLOBS[@]}" 2>/dev/null | wc -l || echo 0)
[ "$UNSAFE_EVAL" -gt 0 ] && add_finding "high" "$UNSAFE_EVAL CSP com 'unsafe-eval'" "" ""

emit_result "$BLINDAR_AGENT" "passed" 0
