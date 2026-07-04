#!/usr/bin/env bash
# Materialização do agente: config-externalization
# Detecta hardcodes que deveriam estar em ENV/DB/i18n.

BLINDAR_AGENT="check-config-externalization"
source "$(dirname "$0")/_lib.sh"

log_section "Check: nada hardcoded no código"

if ! command -v rg >/dev/null 2>&1; then
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

IGNORE=('!node_modules' '!dist' '!build' '!.next' '!**/*.test.*' '!**/*.spec.*'
        '!**/*.stories.*' '!**/__mocks__/**' '!**/*.config.*' '!**/*.env*'
        '!**/*.gen.ts' '!**/locales/**' '!**/i18n/**')

# 1. URLs https://*.com hardcoded em código
log_info "Buscando URLs de produção hardcoded..."
TMP=$(mktemp)
rg -n "https?://[a-z0-9.-]+\.(com|net|io|app|br)" --type ts --type py --type go "${IGNORE[@]}" 2>/dev/null | \
  grep -vE "(localhost|127\.0\.0\.1|0\.0\.0\.0|example\.com|github\.com|w3\.org|schema\.org|@blindar:hardcode-ok)" > "$TMP" || true

URL_COUNT=$(wc -l < "$TMP" || echo 0)
if [ "$URL_COUNT" -gt 0 ]; then
  while IFS=: read -r file line content; do
    [ -z "$file" ] && continue
    add_finding "med" "URL hardcoded (mover pra ENV): $(echo "$content" | xargs | cut -c1-80)" "$file" "$line"
  done < "$TMP"
  log_warn "$URL_COUNT URL(s) de produção hardcoded"
fi
rm -f "$TMP"

# 2. Senhas/tokens hardcoded em código TS/JS (similar ao check-secrets mas escopo mais amplo)
log_info "Buscando password/secret hardcoded em literal..."
TMP=$(mktemp)
rg -n "(password|passwd|api[_-]?key|secret|token)\s*[:=]\s*['\"][a-zA-Z0-9_\-]{8,}['\"]" --type ts --type js --type py "${IGNORE[@]}" 2>/dev/null | \
  grep -v "@blindar:hardcode-ok" > "$TMP" || true

SEC_COUNT=$(wc -l < "$TMP" || echo 0)
if [ "$SEC_COUNT" -gt 0 ]; then
  while IFS=: read -r file line content; do
    [ -z "$file" ] && continue
    add_finding "crit" "Possível secret hardcoded: $(echo "$content" | xargs | cut -c1-80)" "$file" "$line"
  done < "$TMP"
  log_fail "$SEC_COUNT secret(s) hardcoded — mover pra ENV"
fi
rm -f "$TMP"

# 3. .env.example existe e é referenciado
log_info "Verificando .env.example..."
if has_file ".env.example"; then
  log_pass ".env.example existe"
  # Verifica process.env.X que não estão no .env.example
  TMP=$(mktemp)
  rg -ho "process\.env\.[A-Z_]+" --type ts --type js src/ apps/ 2>/dev/null | sort -u > "$TMP"
  USED=$(wc -l < "$TMP" || echo 0)
  if [ "$USED" -gt 0 ]; then
    MISSING_KEYS=$(while read -r usage; do
      key="${usage#process.env.}"
      grep -q "^${key}=" .env.example 2>/dev/null || echo "$key"
    done < "$TMP" | head -20)
    if [ -n "$MISSING_KEYS" ]; then
      echo "$MISSING_KEYS" | while read -r k; do
        [ -z "$k" ] && continue
        add_finding "med" "ENV var '$k' usado no código mas faltando em .env.example" ".env.example" ""
      done
      log_warn "Vars de env usadas no código sem entrada em .env.example"
    else
      log_pass "Todas vars de env documentadas"
    fi
  fi
  rm -f "$TMP"
else
  add_finding "high" ".env.example não existe — devs novos não sabem o que configurar" "" ""
  log_fail ".env.example ausente"
fi

# 4. Cores hex em JSX/TSX (deveriam ser design tokens)
log_info "Buscando cores hex em componentes..."
TMP=$(mktemp)
rg -n "#[0-9a-fA-F]{3,8}\b" --type css "${IGNORE[@]}" 2>/dev/null | \
  grep -vE "(tokens|theme|design-system|@blindar:hardcode-ok)" > "$TMP" || true

COLOR_COUNT=$(wc -l < "$TMP" || echo 0)
if [ "$COLOR_COUNT" -gt 0 ]; then
  add_finding "low" "$COLOR_COUNT cor(es) hex em componente (mover pra design tokens)" "" ""
  log_warn "$COLOR_COUNT cor(es) hex em componente"
fi
rm -f "$TMP"

# Total
TOTAL=${#FINDINGS[@]}
if [ "$TOTAL" -gt 0 ]; then
  # Crits e highs falham; meds e lows passam com warn
  CRITS=$(printf '%s\n' "${FINDINGS[@]}" | grep -c '"severity":"crit"')
  HIGHS=$(printf '%s\n' "${FINDINGS[@]}" | grep -c '"severity":"high"')
  if [ "$CRITS" -gt 0 ] || [ "$HIGHS" -gt 0 ]; then
    emit_result "$BLINDAR_AGENT" "failed" 1
    exit 1
  fi
fi

emit_result "$BLINDAR_AGENT" "passed" 0
exit 0
