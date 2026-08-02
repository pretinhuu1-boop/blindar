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

# jq é OBRIGATÓRIO: a contagem de leaks sai dele. Sem jq, `jq 'length' || echo 0`
# devolvia 0 e o check-secrets — o gate de segredos — reportava PASSED mesmo com
# segredos presentes (falha ABERTA). require_tool marca skipped-por-ferramenta
# (missing_tool=jq no result), nunca aprovação.
require_tool jq "contagem e parsing dos secrets detectados pelo gitleaks"

# Roda no diff staged se tem; senão no working tree.
# --redact: sem isso, os VALORES dos segredos apareciam no stdout/log de CI via
# `tee /dev/stderr`. O check só lê RuleID/File/StartLine, então redigir não perde
# nada necessário e evita vazar o segredo no próprio pipeline que o caça.
TMP=$(mktemp)
if gitleaks protect --staged --redact --report-format=json --report-path="$TMP" 2>&1 | tee /dev/stderr; then
  scope="staged"
elif gitleaks detect --no-git --redact --report-format=json --report-path="$TMP" 2>&1 | tee /dev/stderr; then
  scope="working-tree"
fi

LEAK_COUNT=$(jq 'length' "$TMP" 2>/dev/null || echo 0)

if [ "$LEAK_COUNT" -gt 0 ]; then
  log_fail "$LEAK_COUNT secret(s) detectado(s) (scope: $scope)"
  # `< <(...)` em vez de `jq | while`: num pipe o while roda em SUBSHELL e o array
  # FINDINGS (populado por add_finding) morre com ela → emit_result reportava
  # `failed` com findings:[] (achou segredo mas não listou nenhum).
  while read -r leak; do
    [ -z "$leak" ] && continue
    rule=$(echo "$leak" | jq -r '.RuleID')
    file=$(echo "$leak" | jq -r '.File')
    line=$(echo "$leak" | jq -r '.StartLine')
    add_finding "crit" "Secret hardcoded: $rule" "$file" "$line"
  done < <(jq -c '.[]' "$TMP" 2>/dev/null)
  emit_result "$BLINDAR_AGENT" "failed" 1
  rm -f "$TMP"
  exit 1
fi

rm -f "$TMP"
emit_result "$BLINDAR_AGENT" "passed" 0
exit 0
