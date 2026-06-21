#!/usr/bin/env bash
# Materializa: prompt-injection-defense (OWASP LLM01 — Prompt Injection)
BLINDAR_AGENT="check-prompt-injection-defense"
source "$(dirname "$0")/_lib.sh"
log_section "Check: prompt-injection-defense (LLM01 + tool output RCE)"

if ! command -v rg >/dev/null 2>&1; then emit_result "$BLINDAR_AGENT" "skipped" 0; exit 0; fi
IGNORE=('!node_modules' '!dist' '!.blindar' '!.git' '!**/*.test.*' '!**/*.spec.*')
FAIL=0

# Pré-check: projeto usa LLM? Se não, skip gracioso.
USES_LLM=0
rg -lE "(openai|anthropic|@google/genai|langchain|llamaindex|@vercel/ai|@ai-sdk)" --type ts --type js "${IGNORE[@]}" >/dev/null 2>&1 && USES_LLM=1
rg -lE "^(import|from)\s+(openai|anthropic|google\.generativeai|langchain|llama_index)" --type py "${IGNORE[@]}" >/dev/null 2>&1 && USES_LLM=1
if [ "$USES_LLM" -eq 0 ]; then
  log_info "Projeto não usa LLM detectável — skip."
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

# 1. CRIT — system + user_input concatenado como template string
# Detecta: `${SYSTEM}...${userInput}`, f"{system}...{user_input}", system + user_input
TMP=$(mktemp)
rg -nE "(SYSTEM|system_prompt|systemPrompt|SYSTEM_PROMPT).*\\\$\{.*(user|input|message|query|prompt)" --type ts --type js "${IGNORE[@]}" 2>/dev/null > "$TMP" || true
rg -nE "f['\"].*\{(system|SYSTEM).*\}.*\{(user_input|user_message|query|prompt)\}" --type py "${IGNORE[@]}" 2>/dev/null >> "$TMP" || true
CONCAT=$(wc -l < "$TMP" | tr -d ' ')
rm -f "$TMP"
[ "$CONCAT" -gt 0 ] && add_finding "crit" "$CONCAT system+user concatenados sem delimitador (LLM01 injection)" "" ""

# 2. CRIT — completions.create com prompt único (legacy completion API)
LEGACY=$(rg -cE "(completions|completion)\.create\s*\(\s*\{[^}]*prompt\s*:" --type ts --type js "${IGNORE[@]}" 2>/dev/null | awk -F: '{s+=$2} END {print s+0}')
[ "${LEGACY:-0}" -gt 0 ] && add_finding "high" "$LEGACY uso de legacy completions.create({prompt}) — migrar pra chat.completions com roles" "" ""

# 3. CRIT — tool output em eval/exec/innerHTML (RCE via indirect injection)
TMP=$(mktemp)
rg -nE "(eval|new Function|exec)\s*\(.*(tool|toolResult|tool_output|tool_response|toolCall|function_call)" --type ts --type js --type py "${IGNORE[@]}" 2>/dev/null > "$TMP" || true
rg -nE "(innerHTML|dangerouslySetInnerHTML|outerHTML|document\.write)\s*[=({].*(tool|llm|completion|response\.choices|response\.content)" --type ts --type js "${IGNORE[@]}" 2>/dev/null >> "$TMP" || true
TOOL_RCE=$(wc -l < "$TMP" | tr -d ' ')
rm -f "$TMP"
[ "$TOOL_RCE" -gt 0 ] && add_finding "crit" "$TOOL_RCE tool/LLM output em eval/exec/innerHTML (RCE via injection)" "" ""

# 4. HIGH — RAG/context externo sem spotlighting/delimiter
TMP=$(mktemp)
rg -nE "(context|retrieved|chunks|documents|rag_results|search_results)\s*[+:].*\\\$\{" --type ts --type js "${IGNORE[@]}" 2>/dev/null > "$TMP" || true
RAG_RAW=0
while IFS=: read -r file line content; do
  [ -z "$file" ] && continue
  ctx=$(sed -n "$((line-2)),$((line+5))p" "$file" 2>/dev/null)
  echo "$ctx" | grep -qE "(<context|<user_input|<untrusted|spotlight|untrusted=|escape\()" || RAG_RAW=$((RAG_RAW+1))
done < "$TMP"
rm -f "$TMP"
[ "$RAG_RAW" -gt 2 ] && add_finding "high" "$RAG_RAW contextos RAG/externos injetados sem delimitador ou spotlighting" "" ""

# 5. MED — ausência de injection pattern detection
HAS_DETECT=0
rg -lE "(ignore\s+previous|jailbreak|prompt_injection|injection_filter|guardrail)" --type ts --type js --type py "${IGNORE[@]}" >/dev/null 2>&1 && HAS_DETECT=1
[ "$HAS_DETECT" -eq 0 ] && add_finding "med" "Nenhuma detecção de injection patterns ('ignore previous', jailbreak filters)" "" ""

# 6. HIGH — endpoint que chama LLM sem rate limit visível
TMP=$(mktemp)
rg -lE "(openai|anthropic|@google/genai)\." --type ts --type js "${IGNORE[@]}" 2>/dev/null > "$TMP" || true
NO_RL=0
while IFS= read -r file; do
  [ -z "$file" ] && continue
  grep -qE "(rateLimit|rate_limit|RateLimiter|throttle|express-rate-limit|@nestjs/throttler|p-limit|bottleneck)" "$file" 2>/dev/null || NO_RL=$((NO_RL+1))
done < "$TMP"
rm -f "$TMP"
[ "$NO_RL" -gt 2 ] && add_finding "high" "$NO_RL arquivos com chamada LLM sem rate limit detectável" "" ""

# 7. MED — falta de token cap (max_tokens / max_output_tokens)
TMP=$(mktemp)
rg -lE "(chat\.completions\.create|messages\.create|generateContent)" --type ts --type js "${IGNORE[@]}" 2>/dev/null > "$TMP" || true
NO_CAP=0
while IFS= read -r file; do
  [ -z "$file" ] && continue
  grep -qE "(max_tokens|maxTokens|max_output_tokens|maxOutputTokens)" "$file" 2>/dev/null || NO_CAP=$((NO_CAP+1))
done < "$TMP"
rm -f "$TMP"
[ "$NO_CAP" -gt 0 ] && add_finding "med" "$NO_CAP arquivos chamando LLM sem max_tokens cap (cost abuse risk)" "" ""

[ "$FAIL" -eq 1 ] && { emit_result "$BLINDAR_AGENT" "failed" 1; exit 1; }

# Findings high/crit failam
CRITS=$(printf '%s\n' "${FINDINGS[@]}" | grep -c '"severity":"crit"' 2>/dev/null || echo 0)
HIGHS=$(printf '%s\n' "${FINDINGS[@]}" | grep -c '"severity":"high"' 2>/dev/null || echo 0)
[ "$CRITS" -gt 0 ] && { emit_result "$BLINDAR_AGENT" "failed" 1; exit 1; }
[ "$HIGHS" -gt 0 ] && { emit_result "$BLINDAR_AGENT" "failed" 1; exit 1; }
emit_result "$BLINDAR_AGENT" "passed" 0
