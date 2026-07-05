#!/usr/bin/env bash
# Materialização determinística do agente: mock-killer
# Detecta console.log, TODO sem issue, mock em produção, botões vazios.
# Respeita .blindar/intelligence.yml ignore_paths e markers // @blindar:keep

BLINDAR_AGENT="check-mock-killer"
source "$(dirname "$0")/_lib.sh"

log_section "Check: anti-mock + console.log + TODO órfão"

if ! command -v rg >/dev/null 2>&1; then
  log_fail "ripgrep (rg) requerido. Instale: brew install ripgrep"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

# Paths padrão a ignorar (sobrepostos via intelligence.yml se existir)
IGNORE_GLOBS=(
  '!node_modules' '!vendor' '!dist' '!build' '!.next' '!coverage'
  '!.blindar' '!.git'
  '!**/*.gen.ts' '!**/*.generated.ts' '!**/*.test.*' '!**/*.spec.*'
  '!**/*.stories.*' '!**/__mocks__/**' '!**/fixtures/**'
  '!**/test/**' '!**/tests/**' '!**/__tests__/**'
  '!**/*.dev.ts' '!scripts/**'
)
load_intelligence_globs "$BLINDAR_AGENT"

# 1. console.log/debug/warn em código de produção
log_info "Buscando console.log em código de prod..."
TMP=$(mktemp)
rg -n "console\.(log|debug|warn|trace)\(" --type ts --type js  "${IGNORE_GLOBS[@]}" "${INTEL_GLOBS[@]}" > "$TMP" 2>/dev/null || true

# Filtra linhas com marker @blindar:keep
grep -v "@blindar:keep" "$TMP" > "$TMP.filtered" || true
mv "$TMP.filtered" "$TMP"

CONSOLE_COUNT=$(wc -l < "$TMP" || echo 0)
if [ "$CONSOLE_COUNT" -gt 0 ]; then
  while IFS=: read -r file line content; do
    [ -z "$file" ] && continue
    add_finding "high" "console em produção: $(echo "$content" | xargs)" "$file" "$line"
  done < "$TMP"
  log_fail "$CONSOLE_COUNT console.* em código de produção"
else
  log_pass "Zero console em código de produção"
fi
rm -f "$TMP"

# 2. TODOs sem issue link
log_info "Buscando TODO/FIXME sem issue link..."
TMP=$(mktemp)
rg -n "\b(TODO|FIXME|HACK|XXX)\b" "${IGNORE_GLOBS[@]}" "${INTEL_GLOBS[@]}" 2>/dev/null | \
  grep -vE "TODO\(issue-#[0-9]+\)|TODO\(@[a-z]+\)|@blindar:keep-todo" > "$TMP" || true

TODO_COUNT=$(wc -l < "$TMP" || echo 0)
if [ "$TODO_COUNT" -gt 0 ]; then
  while IFS=: read -r file line content; do
    [ -z "$file" ] && continue
    add_finding "med" "TODO sem issue: $(echo "$content" | xargs)" "$file" "$line"
  done < "$TMP"
  log_warn "$TODO_COUNT TODO/FIXME sem issue link (use TODO(issue-#123): ...)"
else
  log_pass "Todos os TODOs têm issue link ou owner"
fi
rm -f "$TMP"

# 3. Mock/fake/stub fora de pasta de teste
log_info "Buscando mocks em código de produção..."
TMP=$(mktemp)
rg -n "(mock|stub|fake|dummy)[A-Z]" --type ts  "${IGNORE_GLOBS[@]}" "${INTEL_GLOBS[@]}" 2>/dev/null > "$TMP" || true
grep -v "@blindar:keep" "$TMP" > "$TMP.filtered" || true
mv "$TMP.filtered" "$TMP"

MOCK_COUNT=$(wc -l < "$TMP" || echo 0)
if [ "$MOCK_COUNT" -gt 0 ]; then
  while IFS=: read -r file line content; do
    [ -z "$file" ] && continue
    add_finding "high" "mock em produção: $(echo "$content" | xargs)" "$file" "$line"
  done < "$TMP"
  log_fail "$MOCK_COUNT mocks em código de produção"
fi
rm -f "$TMP"

# 4. Botões com handler vazio
log_info "Buscando botões com onClick vazio..."
TMP=$(mktemp)
rg -n "onClick=\{\s*\(\s*\)\s*=>\s*\{\s*\}"   "${IGNORE_GLOBS[@]}" "${INTEL_GLOBS[@]}" > "$TMP" 2>/dev/null || true
EMPTY_CLICK=$(wc -l < "$TMP" || echo 0)
if [ "$EMPTY_CLICK" -gt 0 ]; then
  while IFS=: read -r file line content; do
    [ -z "$file" ] && continue
    add_finding "crit" "Botão sem handler real: $(echo "$content" | xargs)" "$file" "$line"
  done < "$TMP"
  log_fail "$EMPTY_CLICK botão(ões) com onClick vazio — BLOQUEIA release"
fi
rm -f "$TMP"

# 5. Status final
TOTAL=${#FINDINGS[@]}
if [ "$TOTAL" -gt 0 ]; then
  emit_result "$BLINDAR_AGENT" "failed" 1
  exit 1
fi

emit_result "$BLINDAR_AGENT" "passed" 0
exit 0
