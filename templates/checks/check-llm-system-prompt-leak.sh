#!/usr/bin/env bash
# Materializa: llm-system-prompt-leak (OWASP LLM07 — System Prompt Leakage)
# Fonte: docs/book-insights.md § Engenharia de IA (OWASP LLM Top 10 2025).
# Complementa ai-llm-safety (que cobre LLM01/02/05/06/09/10, mas não LLM07).
BLINDAR_AGENT="check-llm-system-prompt-leak"
source "$(dirname "$0")/_lib.sh"
log_section "Check: system prompt leakage (OWASP LLM07)"

if ! command -v rg >/dev/null 2>&1; then emit_result "$BLINDAR_AGENT" "skipped" 0; exit 0; fi

# Só roda se LLM detectado (mesma guarda do ai-llm-safety)
LLM_DETECTED=0
for lib in openai anthropic "@google/genai" langchain "@vercel/ai" llamaindex cohere; do
  grep -qE "\"$lib\":|\"@.*$lib\":" package.json 2>/dev/null && LLM_DETECTED=1
done
[ "$LLM_DETECTED" -eq 0 ] && { emit_result "$BLINDAR_AGENT" "skipped" 0; exit 0; }

IGNORE=(-g '!node_modules' -g '!dist' -g '!build' -g '!.blindar' -g '!.git'
        -g '!**/*.test.*' -g '!**/*.spec.*')
load_intelligence_globs "$BLINDAR_AGENT"

SPVAR="systemPrompt|system_prompt|SYSTEM_PROMPT|SYSTEM_MESSAGE|systemMessage"

# 1. System prompt devolvido numa resposta HTTP (vaza instruções internas ao cliente)
TMP=$(mktemp)
rg -n "(res\.(json|send)|Response\.json|NextResponse\.json|reply\.send)\s*\([^)]*\b($SPVAR)\b" \
  --type ts --type js "${IGNORE[@]}" "${INTEL_GLOBS[@]}" 2>/dev/null | \
  grep -v "@blindar:keep" > "$TMP" || true
while IFS=: read -r file line content; do
  [ -z "$file" ] && continue
  add_finding "high" "System prompt exposto na resposta HTTP — LLM07: $(echo "$content" | xargs | cut -c1-70)" "$file" "$line"
done < "$TMP"
rm -f "$TMP"

# 2. System prompt logado (vaza pro sink de logs — LLM07 via observabilidade)
TMP=$(mktemp)
rg -n "(console\.(log|info|debug)|logger\.(info|debug|log))\s*\([^)]*\b($SPVAR)\b" \
  --type ts --type js "${IGNORE[@]}" "${INTEL_GLOBS[@]}" 2>/dev/null | \
  grep -v "@blindar:keep" > "$TMP" || true
while IFS=: read -r file line content; do
  [ -z "$file" ] && continue
  add_finding "med" "System prompt logado — vaza instruções pro log (LLM07): $(echo "$content" | xargs | cut -c1-70)" "$file" "$line"
done < "$TMP"
rm -f "$TMP"

# Decisão: high reprova; só med (log) vira warning que não bloqueia sozinho.
HIGHS=$(printf '%s\n' "${FINDINGS[@]:-}" | grep -c '"severity":"high"' 2>/dev/null)
if [ "$HIGHS" -gt 0 ]; then
  emit_result "$BLINDAR_AGENT" "failed" 1
  exit 1
fi
emit_result "$BLINDAR_AGENT" "passed" 0
