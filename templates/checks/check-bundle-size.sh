#!/usr/bin/env bash
# size-limit wrapper — bundle JS gzipped <= threshold (default 400KB)

BLINDAR_AGENT="check-bundle-size"
source "$(dirname "$0")/_lib.sh"

log_section "Check: bundle size (size-limit)"

if ! is_nodejs; then
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

# Verifica se size-limit está instalado
if ! grep -qE "\"size-limit\":|\"@size-limit\":" package.json 2>/dev/null; then
  add_finding "med" "Sem size-limit — bundle pode crescer sem alerta" "package.json" ""
  log_warn "size-limit não instalado: npm i -D size-limit @size-limit/preset-app"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

# Verifica config
HAS_CONFIG=0
for f in .size-limit.json .size-limit.cjs .size-limit.js package.json; do
  if grep -qE "\"size-limit\":\s*\[" "$f" 2>/dev/null; then
    HAS_CONFIG=1
    break
  fi
done

if [ "$HAS_CONFIG" -eq 0 ]; then
  add_finding "med" "size-limit instalado mas sem config" "" ""
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

# Roda
log_info "Rodando size-limit..."
TMP=$(mktemp)
if npx size-limit --json > "$TMP" 2>/dev/null; then
  log_pass "Bundle dentro do limite"
  rm -f "$TMP"
  emit_result "$BLINDAR_AGENT" "passed" 0
  exit 0
fi

# Parse falhas
jq -c '.[]' "$TMP" 2>/dev/null | while read -r entry; do
  name=$(echo "$entry" | jq -r '.name')
  size=$(echo "$entry" | jq -r '.size')
  passed=$(echo "$entry" | jq -r '.passed // false')
  if [ "$passed" != "true" ]; then
    add_finding "high" "Bundle '$name' acima do limite ($size bytes gzipped)" "" ""
  fi
done

rm -f "$TMP"
emit_result "$BLINDAR_AGENT" "failed" 1
exit 1
