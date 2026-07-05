#!/usr/bin/env bash
# Materializa agente: ai-llm-safety
# OWASP LLM Top 10: prompt injection, output em eval, sem max_tokens, sem rate limit

BLINDAR_AGENT="check-ai-llm-safety"
source "$(dirname "$0")/_lib.sh"

log_section "Check: AI/LLM safety (OWASP LLM Top 10)"

if ! command -v rg >/dev/null 2>&1; then
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

# Detecta uso de LLM
LLM_DETECTED=0
for lib in openai anthropic "@google/genai" langchain "@vercel/ai" llamaindex cohere; do
  if grep -qE "\"$lib\":|\"@.*$lib\":" package.json 2>/dev/null; then
    LLM_DETECTED=1
    log_info "LLM lib detectada: $lib"
  fi
done

if [ "$LLM_DETECTED" -eq 0 ]; then
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

IGNORE=(-g '!node_modules' -g '!dist' -g '!build' -g '!**/*.test.*')
load_intelligence_globs "$BLINDAR_AGENT"
FAIL=0

# 1. LLM call sem max_tokens (DoS + custo)
log_info "Buscando LLM call sem max_tokens..."
TMP=$(mktemp)
rg -n "(openai|anthropic|gemini)\.\w+\.create\(" --type ts "${IGNORE[@]}" "${INTEL_GLOBS[@]}" -A 10 2>/dev/null | \
  grep -B 10 "\}" | grep -v "max_tokens" > "$TMP" || true
NO_MAX=$(grep -c "create" "$TMP" 2>/dev/null)
if [ "$NO_MAX" -gt 0 ]; then
  add_finding "high" "$NO_MAX LLM call(s) sem max_tokens — DoS + custo descontrolado" "" ""
fi
rm -f "$TMP"

# 2. Concat de userInput em system prompt (prompt injection trivial)
log_info "Buscando prompt injection direta..."
TMP=$(mktemp)
rg -n "['\"][Yy]ou are.*\\\$\{[^}]*input|['\"][Vv]oc[eê].*\\\$\{[^}]*input" --type ts "${IGNORE[@]}" "${INTEL_GLOBS[@]}" > "$TMP" 2>/dev/null || true
INJECTION=$(wc -l < "$TMP" || echo 0)
if [ "$INJECTION" -gt 0 ]; then
  while IFS=: read -r file line content; do
    [ -z "$file" ] && continue
    add_finding "crit" "userInput concat em system prompt: $(echo "$content" | xargs | cut -c1-80)" "$file" "$line"
  done < "$TMP"
  log_fail "$INJECTION prompt injection direta"
  FAIL=1
fi
rm -f "$TMP"

# 3. Output do LLM em eval / queryRawUnsafe / innerHTML
log_info "Buscando output LLM em eval..."
TMP=$(mktemp)
rg -n "(eval|new Function|queryRawUnsafe|innerHTML).*[Cc]ompletion|response\\.content" --type ts "${IGNORE[@]}" "${INTEL_GLOBS[@]}" > "$TMP" 2>/dev/null || true
OUT_EVAL=$(wc -l < "$TMP" || echo 0)
if [ "$OUT_EVAL" -gt 0 ]; then
  add_finding "crit" "Output LLM em eval/queryRawUnsafe/innerHTML — RCE/SQLi/XSS" "" ""
  log_fail "Output LLM sem validação"
  FAIL=1
fi
rm -f "$TMP"

# 4. Sem rate limit por user em endpoints LLM
log_info "Buscando rate limit em endpoints LLM..."
LLM_ENDPOINTS=$(rg -l "openai|anthropic" --type ts "${IGNORE[@]}" "${INTEL_GLOBS[@]}" 2>/dev/null | head -5)
HAS_RATELIMIT=$(rg -l "(rateLimit|@Throttle|@upstash)" --type ts "${IGNORE[@]}" "${INTEL_GLOBS[@]}" 2>/dev/null | head -1)
if [ -n "$LLM_ENDPOINTS" ] && [ -z "$HAS_RATELIMIT" ]; then
  add_finding "high" "Endpoints LLM sem rate limit — 1 user queima sua conta" "" ""
fi

# 5. PII em prompt sem redact
log_info "Buscando PII em prompts..."
TMP=$(mktemp)
rg -n "(messages|prompt|content).*(\\\$\\{[^}]*(email|cpf|phone|name|password))" --type ts "${IGNORE[@]}" "${INTEL_GLOBS[@]}" > "$TMP" 2>/dev/null || true
PII_PROMPT=$(wc -l < "$TMP" || echo 0)
if [ "$PII_PROMPT" -gt 0 ]; then
  add_finding "high" "$PII_PROMPT prompt(s) com PII sem redact — LGPD/GDPR" "" ""
fi
rm -f "$TMP"

# 6. UI sem aviso "é IA"
if grep -lE "(react|vue|svelte|next)" package.json 2>/dev/null | head -1 | grep -q .; then
  HAS_AI_DISCLAIMER=$(rg -l "(é IA|is AI|pode conter erros|may be inaccurate|AI-generated)"   2>/dev/null | head -1)
  if [ -z "$HAS_AI_DISCLAIMER" ]; then
    add_finding "med" "Sem aviso 'pode conter erros' em UI de IA — overreliance risk (LLM09)" "" ""
  fi
fi

# 7. Tool destrutiva sem confirmação humana
TMP=$(mktemp)
rg -n "tools.*delete|tools.*destroy" --type ts "${IGNORE[@]}" "${INTEL_GLOBS[@]}" -A 15 2>/dev/null | \
  grep -v "(requestUserConfirmation|confirm|approval)" > "$TMP" || true
DANGEROUS_TOOLS=$(wc -l < "$TMP" || echo 0)
if [ "$DANGEROUS_TOOLS" -gt 0 ]; then
  add_finding "high" "Tool destrutiva sem confirmação humana (LLM08 excessive agency)" "" ""
fi
rm -f "$TMP"

if [ "$FAIL" -eq 1 ]; then
  emit_result "$BLINDAR_AGENT" "failed" 1
  exit 1
fi

emit_result "$BLINDAR_AGENT" "passed" 0
exit 0
