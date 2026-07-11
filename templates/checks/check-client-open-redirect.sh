#!/usr/bin/env bash
# Materializa: client-open-redirect (DOM — location = input do usuário)
# Fonte: docs/book-insights.md § Rossi. check-security cobre servidor (res.redirect);
# este cobre o lado cliente (navegador), que aquele não pega.
BLINDAR_AGENT="check-client-open-redirect"
source "$(dirname "$0")/_lib.sh"
log_section "Check: open redirect client-side (DOM)"

if ! command -v rg >/dev/null 2>&1; then emit_result "$BLINDAR_AGENT" "skipped" 0; exit 0; fi

IGNORE=(-g '!node_modules' -g '!dist' -g '!build' -g '!.blindar' -g '!.git'
        -g '!**/*.test.*' -g '!**/*.spec.*')
load_intelligence_globs "$BLINDAR_AGENT"

# Fontes de input controladas pelo usuário no cliente
USER_SRC="location\.search|location\.hash|URLSearchParams|searchParams\.get|params\.get|[?&](url|redirect|return|next|continue|dest|target|goto)="

# Sinks de navegação
SINK="location(\.href)?\s*=\s*[a-zA-Z_]|location\.(assign|replace)\s*\(\s*[a-zA-Z_]|window\.open\s*\(\s*[a-zA-Z_]"

# Sinais de validação (se presentes no arquivo, presume-se destino controlado)
VALIDATOR="new URL\(|startsWith\([\"']/[\"']\)|allowlist|whitelist|[Ss]afe|[Ss]anitiz|isValid|validateUrl|@blindar:keep"

# Heurística por arquivo: (usa fonte do usuário) E (atribui a sink de navegação)
# E (não tem validador) → open redirect.
TMP=$(mktemp)
rg -ln "$USER_SRC" --type ts --type js --type tsx "${IGNORE[@]}" "${INTEL_GLOBS[@]}" 2>/dev/null > "$TMP" || true
while IFS= read -r file; do
  [ -z "$file" ] && continue
  rg -q "$SINK" "$file" 2>/dev/null || continue          # tem sink?
  rg -q "$VALIDATOR" "$file" 2>/dev/null && continue      # tem validador? então ok
  LINE=$(rg -n "$SINK" "$file" 2>/dev/null | head -1 | cut -d: -f1)
  CONTENT=$(rg -n "$SINK" "$file" 2>/dev/null | head -1 | cut -d: -f2-)
  add_finding "high" "Redirect client-side com input do usuário sem allowlist — open redirect: $(echo "$CONTENT" | xargs | cut -c1-60)" "$file" "${LINE:-}"
done < "$TMP"
rm -f "$TMP"

CRITS=$(printf '%s\n' "${FINDINGS[@]:-}" | grep -c '"severity":"crit"' 2>/dev/null)
HIGHS=$(printf '%s\n' "${FINDINGS[@]:-}" | grep -c '"severity":"high"' 2>/dev/null)
if [ "$CRITS" -gt 0 ] || [ "$HIGHS" -gt 0 ]; then
  emit_result "$BLINDAR_AGENT" "failed" 1
  exit 1
fi
emit_result "$BLINDAR_AGENT" "passed" 0
