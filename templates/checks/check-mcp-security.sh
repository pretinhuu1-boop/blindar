#!/usr/bin/env bash
# Materializa: mcp-security (OWASP LLM05/LLM07/LLM08 — MCP supply chain + agency)
BLINDAR_AGENT="check-mcp-security"
source "$(dirname "$0")/_lib.sh"
log_section "Check: mcp-security (MCPs ativos vs whitelist)"

# Resolve paths de config MCP por plataforma
MCP_CONFIGS=()
[ -f "$HOME/.claude.json" ] && MCP_CONFIGS+=("$HOME/.claude.json")
[ -f "$HOME/.cursor/mcp.json" ] && MCP_CONFIGS+=("$HOME/.cursor/mcp.json")
[ -f "$HOME/Library/Application Support/Claude/claude_desktop_config.json" ] && MCP_CONFIGS+=("$HOME/Library/Application Support/Claude/claude_desktop_config.json")
[ -n "${APPDATA:-}" ] && [ -f "$APPDATA/Claude/claude_desktop_config.json" ] && MCP_CONFIGS+=("$APPDATA/Claude/claude_desktop_config.json")
[ -f "./.mcp.json" ] && MCP_CONFIGS+=("./.mcp.json")
[ -f "./.cursor/mcp.json" ] && MCP_CONFIGS+=("./.cursor/mcp.json")

# Skip gracioso se nenhuma config
if [ "${#MCP_CONFIGS[@]}" -eq 0 ]; then
  log_info "Nenhuma config MCP encontrada — skip."
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

# Catálogo whitelist
CATALOG=""
for candidate in \
  "$(dirname "$0")/../mcp-catalog.yml" \
  "$(dirname "$0")/../../templates/mcp-catalog.yml" \
  ".blindar/mcp-catalog.yml"; do
  [ -f "$candidate" ] && CATALOG="$candidate" && break
done

if [ -z "$CATALOG" ]; then
  log_warn "Catálogo mcp-catalog.yml não encontrado — pulando whitelist check."
fi

FAIL=0

# Helper: extrai nomes de MCP de um JSON config (sem jq, parsing leve)
# Procura por chaves dentro de "mcpServers": { "NAME": {...}, ... }
extract_mcp_names() {
  local f="$1"
  # Pega bloco mcpServers e extrai chaves de primeiro nível dentro dele
  awk '
    /"mcpServers"[[:space:]]*:/ { in_block=1; depth=0; next }
    in_block && /\{/ { depth++ }
    in_block && /\}/ { depth--; if (depth<=0) { in_block=0 } }
    in_block && depth==1 && /^[[:space:]]*"[^"]+"[[:space:]]*:[[:space:]]*\{/ {
      match($0, /"[^"]+"/)
      name=substr($0, RSTART+1, RLENGTH-2)
      print name
    }
  ' "$f" 2>/dev/null
}

# Helper: extrai env vars com valor em plain text (sem ${env:...})
extract_plaintext_secrets() {
  local f="$1"
  grep -nE "\"(GITHUB_TOKEN|API_KEY|SECRET|TOKEN|PASSWORD|ACCESS_KEY|PRIVATE_KEY)[^\"]*\"[[:space:]]*:[[:space:]]*\"[^$\"][^\"]*\"" "$f" 2>/dev/null \
    | grep -vE '\$\{|\$env:|process\.env'
}

TOTAL_MCPS=0
NOT_WHITELISTED=0
CAPABILITY_BLEED=0
PLAINTEXT_SECRETS=0
LOCAL_NO_HASH=0
MISSING_VENDOR=0

for cfg in "${MCP_CONFIGS[@]}"; do
  log_info "Auditando: $cfg"

  # MCPs no config
  while IFS= read -r mcp_name; do
    [ -z "$mcp_name" ] && continue
    TOTAL_MCPS=$((TOTAL_MCPS+1))

    # 2. CRIT — capability bleed no nome
    if echo "$mcp_name" | grep -qiE "(shell|exec|eval|sudo|admin|system-(call|run))"; then
      CAPABILITY_BLEED=$((CAPABILITY_BLEED+1))
      add_finding "crit" "MCP '$mcp_name' tem nome com capability bleed (shell/exec/eval/sudo/admin)" "$cfg" ""
    fi

    # 3. HIGH — não está na whitelist
    if [ -n "$CATALOG" ]; then
      if ! grep -qiE "name:\s*[\"']?.*${mcp_name}" "$CATALOG" 2>/dev/null; then
        NOT_WHITELISTED=$((NOT_WHITELISTED+1))
        add_finding "high" "MCP '$mcp_name' não está em mcp-catalog.yml (review manual)" "$cfg" ""
      fi
    fi
  done < <(extract_mcp_names "$cfg")

  # 4. CRIT — secrets em plain text
  while IFS= read -r leak; do
    [ -z "$leak" ] && continue
    PLAINTEXT_SECRETS=$((PLAINTEXT_SECRETS+1))
    line_num=$(echo "$leak" | cut -d: -f1)
    add_finding "crit" "Token/secret em plain text no config MCP" "$cfg" "$line_num"
  done < <(extract_plaintext_secrets "$cfg")

  # 5. MED — local binary sem hash documentado
  # Padrão: "command": "/path/binary" (path absoluto ou relativo, não system bin)
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    line_num=$(echo "$line" | cut -d: -f1)
    LOCAL_NO_HASH=$((LOCAL_NO_HASH+1))
    add_finding "med" "MCP local binary sem hash/checksum documentado" "$cfg" "$line_num"
  done < <(grep -nE "\"command\"[[:space:]]*:[[:space:]]*\"(/|\\./|\\.\\./|[A-Za-z]:\\\\)" "$cfg" 2>/dev/null)

  # 6. LOW — falta de campo version/vendor
  # Heurística: se config menciona MCPs custom (não npx/uvx oficial) sem "version" no bloco
  has_npx_official=$(grep -cE "\"command\"[[:space:]]*:[[:space:]]*\"(npx|uvx|deno|bunx)\"" "$cfg" 2>/dev/null || echo 0)
  has_version=$(grep -cE "\"version\"[[:space:]]*:" "$cfg" 2>/dev/null || echo 0)
  if [ "${has_npx_official:-0}" -eq 0 ] && [ "${has_version:-0}" -eq 0 ] && [ "$TOTAL_MCPS" -gt 0 ]; then
    MISSING_VENDOR=$((MISSING_VENDOR+1))
  fi
done

[ "$MISSING_VENDOR" -gt 0 ] && add_finding "low" "$MISSING_VENDOR config(s) MCP sem campo version/vendor explícito" "" ""

log_info "Inventário: $TOTAL_MCPS MCPs ativos | $NOT_WHITELISTED fora whitelist | $CAPABILITY_BLEED capability bleed | $PLAINTEXT_SECRETS secrets vazados"

[ "$FAIL" -eq 1 ] && { emit_result "$BLINDAR_AGENT" "failed" 1; exit 1; }

# Findings high/crit failam
CRITS=$(printf '%s\n' "${FINDINGS[@]}" | grep -c '"severity":"crit"' 2>/dev/null || echo 0)
HIGHS=$(printf '%s\n' "${FINDINGS[@]}" | grep -c '"severity":"high"' 2>/dev/null || echo 0)
[ "$CRITS" -gt 0 ] && { emit_result "$BLINDAR_AGENT" "failed" 1; exit 1; }
[ "$HIGHS" -gt 0 ] && { emit_result "$BLINDAR_AGENT" "failed" 1; exit 1; }
emit_result "$BLINDAR_AGENT" "passed" 0
