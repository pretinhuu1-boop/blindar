#!/usr/bin/env bash
# Materializa: rate-limit (ASVS V11.3)
BLINDAR_AGENT="check-rate-limit"
source "$(dirname "$0")/_lib.sh"
log_section "Check: rate-limit"

if ! command -v rg >/dev/null 2>&1; then emit_result "$BLINDAR_AGENT" "skipped" 0; exit 0; fi

IGNORE=('!node_modules' '!dist' '!**/*.test.*')

HAS_RL=$(rg -cE "(rate-limit|rateLimit|@upstash/ratelimit|express-rate-limit|@nestjs/throttler)" --type ts --type js "${IGNORE[@]}" 2>/dev/null | wc -l || echo 0)
HAS_ROUTES=$(rg -cE "(app\.(post|put|delete)|@Post\(|@Put\(|@Delete\()" --type ts "${IGNORE[@]}" 2>/dev/null | wc -l || echo 0)

if [ "$HAS_ROUTES" -gt 0 ] && [ "$HAS_RL" -eq 0 ]; then
  add_finding "high" "Rotas POST/PUT/DELETE sem rate-limit detectável" "" ""
  emit_result "$BLINDAR_AGENT" "failed" 1
  exit 1
fi

# Endpoints sensíveis sem rate limit explícito (login, signup, reset, otp)
SENSITIVE=$(rg -lE "(login|signin|signup|register|reset.password|verify.otp|forgot.password)" --type ts "${IGNORE[@]}" 2>/dev/null | wc -l || echo 0)
SENSITIVE_RL=$(rg -lE "rate.?limit" --type ts "${IGNORE[@]}" 2>/dev/null | xargs grep -lE "(login|signup|reset|otp)" 2>/dev/null | wc -l || echo 0)

if [ "$SENSITIVE" -gt 0 ] && [ "$SENSITIVE_RL" -eq 0 ]; then
  add_finding "high" "Endpoint sensível (login/reset/otp) sem rate-limit dedicado" "" ""
fi

emit_result "$BLINDAR_AGENT" "passed" 0
