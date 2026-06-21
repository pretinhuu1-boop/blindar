#!/usr/bin/env bash
# Materialização determinística do agente: runtime-secrets + supply-chain (parcial)
# Detecta secrets hardcoded usando gitleaks.
# Exit 0 se zero secrets. Exit 1 se achar.

BLINDAR_AGENT="check-secrets"
source "$(dirname "$0")/_lib.sh"

log_section "Check: secrets hardcoded (gitleaks)"

if ! command -v gitleaks >/dev/null 2>&1; then
  log_warn "gitleaks não instalado. Instale: brew install gitleaks  (ou: go install github.com/gitleaks/gitleaks/v8@latest)"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

# Roda no diff staged se tem; senão no working tree
TMP=$(mktemp)
if gitleaks protect --staged --report-format=json --report-path="$TMP" 2>&1 | tee /dev/stderr; then
  scope="staged"
elif gitleaks detect --no-git --report-format=json --report-path="$TMP" 2>&1 | tee /dev/stderr; then
  scope="working-tree"
fi

LEAK_COUNT=$(jq 'length' "$TMP" 2>/dev/null || echo 0)

if [ "$LEAK_COUNT" -gt 0 ]; then
  log_fail "$LEAK_COUNT secret(s) detectado(s) (scope: $scope)"
  jq -c '.[]' "$TMP" 2>/dev/null | while read -r leak; do
    rule=$(echo "$leak" | jq -r '.RuleID')
    file=$(echo "$leak" | jq -r '.File')
    line=$(echo "$leak" | jq -r '.StartLine')
    add_finding "crit" "Secret hardcoded: $rule" "$file" "$line"
  done
  emit_result "$BLINDAR_AGENT" "failed" 1
  rm -f "$TMP"
  exit 1
fi

rm -f "$TMP"
emit_result "$BLINDAR_AGENT" "passed" 0
exit 0
