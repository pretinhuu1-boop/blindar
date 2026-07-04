#!/usr/bin/env bash
# Termination calculator: lê .blindar/results/aggregate.json e decide se release está liberada.
# Decisão MATEMÁTICA, não opinião do LLM.
#
# Critério de termination v0.22:
#   - 0 crit confirmados
#   - ≤ 2 high acknowledged (em .accept-risk.md)
#   - Cobertura crítica ≥ 80%
#   - CI verde streak ≥ 3
#
# Exit:
#   0 = termination atingida, release liberada
#   1 = crit aberto (bloqueia)
#   2 = high > 2 sem accept-risk (bloqueia)
#   3 = cobertura insuficiente
#   4 = CI streak insuficiente

set -euo pipefail

BLINDAR_DIR="${BLINDAR_DIR:-.blindar}"
AGGREGATE="$BLINDAR_DIR/results/aggregate.json"
ACCEPT_RISK="$BLINDAR_DIR/accept-risk.md"

if [ ! -f "$AGGREGATE" ]; then
  echo "❌ $AGGREGATE não encontrado. Rode: bash scripts/blindar/run-all.sh primeiro." >&2
  exit 1
fi

# Critérios configuráveis
MAX_CRIT="${MAX_CRIT:-0}"
MAX_HIGH_ACCEPTED="${MAX_HIGH_ACCEPTED:-2}"
MIN_COVERAGE_PCT="${MIN_COVERAGE_PCT:-80}"
MIN_CI_GREEN_STREAK="${MIN_CI_GREEN_STREAK:-3}"

CRITS=$(jq '.findings_by_severity.crit // 0' "$AGGREGATE")
HIGHS=$(jq '.findings_by_severity.high // 0' "$AGGREGATE")
MEDS=$(jq '.findings_by_severity.med // 0' "$AGGREGATE")
LOWS=$(jq '.findings_by_severity.low // 0' "$AGGREGATE")

# Conta highs em accept-risk
HIGH_ACCEPTED=0
if [ -f "$ACCEPT_RISK" ]; then
  HIGH_ACCEPTED=$(grep -c "^- \[x\].*high" "$ACCEPT_RISK" 2>/dev/null)
fi
HIGH_UNACCEPTED=$((HIGHS - HIGH_ACCEPTED))

echo "═══ blindar termination check ═══"
echo ""
echo "  Crits abertos          : $CRITS  (max permitido: $MAX_CRIT)"
echo "  Highs total            : $HIGHS"
echo "  Highs em accept-risk   : $HIGH_ACCEPTED"
echo "  Highs sem accept-risk  : $HIGH_UNACCEPTED  (max permitido: $MAX_HIGH_ACCEPTED)"
echo "  Meds                   : $MEDS"
echo "  Lows                   : $LOWS"
echo ""

EXIT_CODE=0

if [ "$CRITS" -gt "$MAX_CRIT" ]; then
  echo "❌ CRIT aberto — release BLOQUEADA"
  EXIT_CODE=1
fi

if [ "$HIGH_UNACCEPTED" -gt "$MAX_HIGH_ACCEPTED" ]; then
  echo "❌ Highs sem accept-risk > $MAX_HIGH_ACCEPTED — release BLOQUEADA"
  echo "   Aceite os highs em $ACCEPT_RISK com checkbox marcado [x]"
  [ "$EXIT_CODE" -eq 0 ] && EXIT_CODE=2
fi

# Coverage check (se disponível)
if [ -f "coverage/coverage-summary.json" ]; then
  COVERAGE=$(jq -r '.total.statements.pct // 0' coverage/coverage-summary.json)
  if (( $(echo "$COVERAGE < $MIN_COVERAGE_PCT" | bc -l 2>/dev/null) )); then
    echo "❌ Coverage $COVERAGE% < $MIN_COVERAGE_PCT% — release BLOQUEADA"
    [ "$EXIT_CODE" -eq 0 ] && EXIT_CODE=3
  fi
else
  echo "⚠  coverage-summary.json não encontrado (rode npm run test:coverage)"
fi

# CI green streak (lê última N runs via gh CLI)
if command -v gh >/dev/null 2>&1; then
  STREAK=$(gh run list --limit 5 --json conclusion --jq '[.[] | select(.conclusion == "success")] | length' 2>/dev/null || echo 0)
  if [ "$STREAK" -lt "$MIN_CI_GREEN_STREAK" ]; then
    echo "❌ CI green streak $STREAK < $MIN_CI_GREEN_STREAK — release BLOQUEADA"
    [ "$EXIT_CODE" -eq 0 ] && EXIT_CODE=4
  else
    echo "✅ CI green streak: $STREAK"
  fi
fi

if [ "$EXIT_CODE" -eq 0 ]; then
  echo ""
  echo "✅ ✅ ✅  TERMINATION ATINGIDA — release LIBERADA  ✅ ✅ ✅"
fi

exit $EXIT_CODE
