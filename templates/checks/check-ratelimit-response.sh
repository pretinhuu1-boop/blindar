#!/usr/bin/env bash
# Materializa: ratelimit-response — rota com @limiter.limit (slowapi) sem
# 'response: Response' no parâmetro. Bug real: /change-password sem response:
# Response → slowapi 500 ao injetar headers de rate-limit.
BLINDAR_AGENT="check-ratelimit-response"
source "$(dirname "$0")/_lib.sh"
log_section "Check: ratelimit-response (slowapi @limiter sem response: Response)"

if ! command -v rg >/dev/null 2>&1; then emit_result "$BLINDAR_AGENT" "skipped" 0; exit 0; fi
IGNORE=(-g '!node_modules' -g '!dist' -g '!.git' -g '!**/*.test.*')
load_intelligence_globs "$BLINDAR_AGENT"
FAIL=0

LIM=$(rg -c "@limiter\.limit" --type py "${IGNORE[@]}" "${INTEL_GLOBS[@]}" 2>/dev/null | wc -l)
if [ "$LIM" -gt 0 ]; then
  RESP=$(rg -c "response:\s*Response" --type py "${IGNORE[@]}" "${INTEL_GLOBS[@]}" 2>/dev/null | wc -l)
  if [ "$RESP" -eq 0 ]; then
    add_finding "high" "@limiter.limit (slowapi) sem 'response: Response' nos handlers — o slowapi injeta headers de rate-limit via esse parâmetro; sem ele, 500 em runtime" "" ""
    FAIL=1
  fi
fi

if [ "$FAIL" -eq 1 ]; then emit_result "$BLINDAR_AGENT" "failed" 1; exit 1; fi
emit_result "$BLINDAR_AGENT" "passed" 0
