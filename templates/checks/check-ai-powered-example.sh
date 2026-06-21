#!/usr/bin/env bash
# Exemplo de check AI-powered: delega análise nuançada pro Claude via API
# Demonstra padrão: shell coleta evidências → Claude analisa → JSON estruturado.
#
# Pré-requisitos:
#   - ANTHROPIC_API_KEY no env
#   - curl + jq
#
# Padrão pra outros checks que precisam de "julgamento":
#   1. Shell coleta arquivos/contexto (deterministico)
#   2. Monta prompt com evidências
#   3. Envia pra API com tool use forçando JSON output
#   4. Parse JSON + emit_result
#
# Default: skipped se API_KEY ausente (não bloqueia CI).

BLINDAR_AGENT="check-ai-powered-example"
source "$(dirname "$0")/_lib.sh"
log_section "Check: ai-powered example (Claude API)"

if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
  log_info "ANTHROPIC_API_KEY ausente — skipped (defina pra ativar AI checks)"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

if ! command -v jq >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
  log_warn "curl ou jq ausentes — skipped"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

# 1. Coleta evidência: README + package.json (limitado pra economizar token)
README=$(head -c 4000 README.md 2>/dev/null || echo "")
PKG=$(head -c 2000 package.json 2>/dev/null || echo "")

if [ -z "$README" ] && [ -z "$PKG" ]; then
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

# 2. Monta prompt
PROMPT=$(cat <<EOF
Você é o agente \"product-clarity-reviewer\" do blindar.
Analise se este README + package.json comunicam claramente:
  - O que o produto faz (1 frase clara)
  - Pra quem (ICP)
  - Como rodar localmente (≤ 5 passos)
  - Sem jargão desnecessário

README (truncado):
\`\`\`
$README
\`\`\`

package.json (truncado):
\`\`\`
$PKG
\`\`\`

Responda APENAS JSON válido no formato:
{"severity":"crit|high|med|low|none","findings":[{"message":"...","fix":"..."}]}
EOF
)

# 3. Chama API (modelo barato pra triage)
RESPONSE=$(curl -sS https://api.anthropic.com/v1/messages \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d "$(jq -n --arg p "$PROMPT" '{
    model: "claude-haiku-4-5-20251001",
    max_tokens: 1024,
    messages: [{role:"user", content: $p}]
  }')" 2>/dev/null)

if [ -z "$RESPONSE" ]; then
  log_warn "API call falhou"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

# 4. Extrai texto + parse JSON
TEXT=$(echo "$RESPONSE" | jq -r '.content[0].text // ""' 2>/dev/null)
[ -z "$TEXT" ] && { emit_result "$BLINDAR_AGENT" "skipped" 0; exit 0; }

# Tenta extrair JSON (resposta pode vir com markdown around)
JSON=$(echo "$TEXT" | grep -oE '\{[^{}]*"severity"[^{}]*\}' | head -1)
[ -z "$JSON" ] && JSON=$(echo "$TEXT" | sed -n '/^{/,/^}/p')

SEV=$(echo "$JSON" | jq -r '.severity // "none"' 2>/dev/null)

case "$SEV" in
  crit) FAIL=1; SEVERITY="crit" ;;
  high) FAIL=1; SEVERITY="high" ;;
  med)  FAIL=0; SEVERITY="med" ;;
  low)  FAIL=0; SEVERITY="low" ;;
  *)    emit_result "$BLINDAR_AGENT" "passed" 0; exit 0 ;;
esac

MSG=$(echo "$JSON" | jq -r '.findings[0].message // "AI flagged issue"' 2>/dev/null)
FIX=$(echo "$JSON" | jq -r '.findings[0].fix // ""' 2>/dev/null)

add_finding "$SEVERITY" "[AI] $MSG${FIX:+ Fix: $FIX}" "README.md" ""

if [ "$FAIL" -eq 1 ]; then
  emit_result "$BLINDAR_AGENT" "failed" 1
  exit 1
fi
emit_result "$BLINDAR_AGENT" "passed" 0
