#!/usr/bin/env bash
# Materializa: mcp-recommender — lê catalog + detecta stack + lista sugestões
# Não instala nada — só sugere. Decisão final = operador.

BLINDAR_AGENT="check-mcp-recommended"
source "$(dirname "$0")/_lib.sh"
log_section "Check: MCP recommender (sugestões pra sua stack)"

CATALOG=""
for path in templates/mcp-catalog.yml ~/.claude/skills/blindar/templates/mcp-catalog.yml; do
  [ -f "$path" ] && CATALOG="$path" && break
done

if [ -z "$CATALOG" ]; then
  log_warn "Catálogo de MCPs não encontrado"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

# Detecta stack
SUGGEST=()

# Supabase
if grep -qE "\"@supabase/supabase-js\":" package.json 2>/dev/null || \
   grep -qE "SUPABASE_" .env.example 2>/dev/null; then
  SUGGEST+=("Supabase MCP (oficial, safety: high) — DB schema, edge functions, logs")
fi

# GitHub
if git remote -v 2>/dev/null | grep -q github.com; then
  SUGGEST+=("GitHub MCP (oficial Anthropic, safety: high) — issues, PRs, code search")
fi

# Figma
if grep -rE "figma\.com" . --include="*.md" --include="*.ts" 2>/dev/null | head -1 | grep -q . || \
   has_dir "design-tokens"; then
  SUGGEST+=("Figma MCP (oficial, safety: high) — design-to-code")
fi

# Notion
if grep -qE "NOTION_" .env.example 2>/dev/null || \
   grep -qE "\"@notionhq/" package.json 2>/dev/null; then
  SUGGEST+=("Notion MCP (oficial, safety: high) — docs/runbooks")
fi

# HuggingFace
if grep -qE "\"@huggingface/" package.json 2>/dev/null || \
   grep -qE "huggingface_hub" requirements.txt 2>/dev/null; then
  SUGGEST+=("Hugging Face MCP (oficial, safety: high) — models + datasets")
fi

# Cloudflare
if has_file "wrangler.toml" || grep -qE "\"@cloudflare/" package.json 2>/dev/null; then
  SUGGEST+=("Cloudflare MCP (oficial, safety: med) — Workers + DNS + Pages")
fi

# MongoDB
if grep -qE "\"mongodb\":" package.json 2>/dev/null; then
  SUGGEST+=("MongoDB MCP (oficial, safety: med) — schema + queries")
fi

# Linear
if grep -qE "LINEAR_" .env.example 2>/dev/null; then
  SUGGEST+=("Linear MCP (oficial, safety: high) — issue tracking")
fi

# Google Workspace
if grep -qE "GOOGLE_(CALENDAR|GMAIL)" .env.example 2>/dev/null; then
  SUGGEST+=("Google Calendar+Gmail MCP (oficial, safety: high) — schedule + email")
fi

# Output sugestões
echo ""
if [ "${#SUGGEST[@]}" -eq 0 ]; then
  log_info "Nenhum MCP detectado pra sua stack"
else
  log_pass "MCPs sugeridos pra esta stack (${#SUGGEST[@]}):"
  echo ""
  for s in "${SUGGEST[@]}"; do
    echo "  • $s"
  done
  echo ""
  echo "Pra instalar, adicione em ~/.claude.json conforme docs do MCP."
  echo "Catálogo completo: $CATALOG"
fi

# Sempre 'passed' — sugestão não é blocking
emit_result "$BLINDAR_AGENT" "passed" 0
exit 0
