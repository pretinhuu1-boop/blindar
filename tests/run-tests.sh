#!/usr/bin/env bash
# Test suite do próprio blindar.
# Roda cada fixture contra cada check, verifica resultado esperado.
#
# Uso: bash tests/run-tests.sh
# Exit 0 = todos os testes passaram

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"
CHECKS_DIR="$SKILL_DIR/templates/checks"
FIXTURES_DIR="$SCRIPT_DIR/fixtures"

if [ -t 1 ]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; BOLD='\033[1m'; RESET='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; BOLD=''; RESET=''
fi

PASS_COUNT=0
FAIL_COUNT=0
FAIL_LIST=()

# Cada caso: "fixture | check | expected_status (passed|failed)"
TEST_CASES=(
  "clean-project | check-mock-killer.sh | passed"
  "clean-project | check-secrets.sh | passed"
  "clean-project | check-config-externalization.sh | passed"
  "project-with-mocks | check-mock-killer.sh | failed"
  "project-with-secrets | check-config-externalization.sh | failed"
  "project-multi-tenant-bad | check-prisma-schema.sh | failed"
)

echo "${BOLD}═══ blindar test suite ═══${RESET}"
echo "Fixtures: $FIXTURES_DIR"
echo "Checks:   $CHECKS_DIR"
echo ""

for tc in "${TEST_CASES[@]}"; do
  IFS='|' read -r fixture check expected <<< "$tc"
  fixture=$(echo "$fixture" | xargs)
  check=$(echo "$check" | xargs)
  expected=$(echo "$expected" | xargs)

  fixture_dir="$FIXTURES_DIR/$fixture"
  check_script="$CHECKS_DIR/$check"

  if [ ! -d "$fixture_dir" ]; then
    echo "${YELLOW}SKIP:${RESET} fixture $fixture não existe"
    continue
  fi

  if [ ! -f "$check_script" ]; then
    echo "${YELLOW}SKIP:${RESET} check $check não existe"
    continue
  fi

  printf "%-30s %-40s expected=%-7s " "$fixture" "$check" "$expected"

  # Roda check dentro da fixture, capturando exit code
  ACTUAL_OUTPUT=$(cd "$fixture_dir" && bash "$check_script" 2>&1 > /dev/null; echo "EXIT=$?")
  EXIT_CODE=$(echo "$ACTUAL_OUTPUT" | grep -oE "EXIT=[0-9]+" | tail -1 | cut -d= -f2)
  EXIT_CODE=${EXIT_CODE:-0}

  if [ "$expected" = "passed" ] && [ "$EXIT_CODE" -eq 0 ]; then
    actual="passed"
  elif [ "$expected" = "failed" ] && [ "$EXIT_CODE" -ne 0 ]; then
    actual="failed"
  else
    actual="WRONG (exit=$EXIT_CODE)"
  fi

  if [ "$actual" = "$expected" ]; then
    echo "${GREEN}✓ $actual${RESET}"
    PASS_COUNT=$((PASS_COUNT+1))
  else
    echo "${RED}✗ $actual${RESET}"
    FAIL_COUNT=$((FAIL_COUNT+1))
    FAIL_LIST+=("$fixture / $check (expected=$expected, got=$actual)")
  fi
done

# ── Gate de auto-teste dos checks (pares vuln/limpo verificados) ───────────
echo ""
echo "${BOLD}── check self-test (fixture pairs + cobertura) ──${RESET}"
if bash "$SKILL_DIR/scripts/check-selftest.sh"; then
  PASS_COUNT=$((PASS_COUNT+1))
else
  FAIL_COUNT=$((FAIL_COUNT+1))
  FAIL_LIST+=("scripts/check-selftest.sh (regressão em par verificado)")
fi

# ── Testes de spec (Node, v0.43 — ROADMAP #4/#16/#17) ──────────────────────
if command -v node >/dev/null 2>&1; then
  echo ""
  echo "${BOLD}── specs (reproducibility / sbom / race-fuzz) ──${RESET}"
  if node "$SCRIPT_DIR/specs.test.js"; then
    PASS_COUNT=$((PASS_COUNT+1))
  else
    FAIL_COUNT=$((FAIL_COUNT+1))
    FAIL_LIST+=("tests/specs.test.js")
  fi
  echo ""
  echo "${BOLD}── módulo 17 (blindar ataque — recon passivo) ──${RESET}"
  if node "$SCRIPT_DIR/attack-recon.test.js"; then
    PASS_COUNT=$((PASS_COUNT+1))
  else
    FAIL_COUNT=$((FAIL_COUNT+1))
    FAIL_LIST+=("tests/attack-recon.test.js")
  fi
else
  echo "${YELLOW}SKIP:${RESET} node ausente — specs.test.js não rodado"
fi

echo ""
echo "${BOLD}═══ RESUMO ═══${RESET}"
echo "${GREEN}Passed: $PASS_COUNT${RESET}"
echo "${RED}Failed: $FAIL_COUNT${RESET}"

if [ "$FAIL_COUNT" -gt 0 ]; then
  echo ""
  echo "${RED}Falhas:${RESET}"
  for f in "${FAIL_LIST[@]}"; do
    echo "  • $f"
  done
  exit 1
fi

echo ""
echo "${GREEN}${BOLD}✅ TODOS OS TESTES PASSARAM${RESET}"
echo ""
echo "Próximo nível: adicionar mais fixtures (project-with-cvv, project-no-csp,"
echo "project-bad-perf, etc.) — ver tests/fixtures/ pra padrão."
exit 0
