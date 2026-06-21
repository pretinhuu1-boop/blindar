#!/usr/bin/env bash
# Materializa: functional-e2e
BLINDAR_AGENT="check-functional-e2e"
source "$(dirname "$0")/_lib.sh"
log_section "Check: functional-e2e (Playwright/Cypress)"

is_nodejs || { emit_result "$BLINDAR_AGENT" "skipped" 0; exit 0; }

# 1. Tem framework E2E instalado
E2E=""
grep -qE "\"@playwright/test\":" package.json 2>/dev/null && E2E="playwright"
grep -qE "\"cypress\":" package.json 2>/dev/null && E2E="cypress"
grep -qE "\"@testing-library/" package.json 2>/dev/null && [ -z "$E2E" ] && E2E="testing-library-only"

if [ -z "$E2E" ]; then
  add_finding "high" "Nenhum framework E2E instalado (Playwright/Cypress)" "" ""
  emit_result "$BLINDAR_AGENT" "failed" 1
  exit 1
fi

# 2. Existe pasta de testes E2E
E2E_DIR=""
for d in e2e tests/e2e cypress playwright __e2e__; do
  [ -d "$d" ] && E2E_DIR="$d" && break
done

if [ -z "$E2E_DIR" ]; then
  add_finding "high" "$E2E instalado mas sem pasta de testes (e2e/, cypress/, playwright/)" "" ""
  emit_result "$BLINDAR_AGENT" "failed" 1
  exit 1
fi

# 3. Conta testes
TEST_COUNT=$(find "$E2E_DIR" -name "*.spec.*" -o -name "*.test.*" -o -name "*.cy.*" 2>/dev/null | wc -l)
if [ "$TEST_COUNT" -eq 0 ]; then
  add_finding "high" "Pasta $E2E_DIR existe mas zero testes" "$E2E_DIR" ""
  emit_result "$BLINDAR_AGENT" "failed" 1
  exit 1
fi

log_info "Framework: $E2E, testes em $E2E_DIR: $TEST_COUNT"

# 4. CI roda E2E
HAS_CI_E2E=$(grep -lE "(playwright|cypress|npx playwright|npx cypress)" .github/workflows/*.yml 2>/dev/null | wc -l)
[ "$HAS_CI_E2E" -eq 0 ] && add_finding "med" "E2E configurado mas não roda em CI (.github/workflows/)" "" ""

# 5. Smoke test do golden path existe?
GOLDEN=$(find "$E2E_DIR" \( -name "*smoke*" -o -name "*golden*" -o -name "*critical*" \) 2>/dev/null | wc -l)
[ "$GOLDEN" -eq 0 ] && add_finding "low" "Sem teste E2E marcado como smoke/golden/critical" "" ""

emit_result "$BLINDAR_AGENT" "passed" 0
