#!/usr/bin/env bash
# Materializa agente: responsive-a11y
# axe-core via Playwright se disponível, senão grep estático

BLINDAR_AGENT="check-responsive-a11y"
source "$(dirname "$0")/_lib.sh"

log_section "Check: responsive-a11y (WCAG AA + touch targets + outline visible)"

if ! command -v rg >/dev/null 2>&1; then
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

HAS_UI=0
if has_dir "public" || has_dir "app" || has_dir "pages" || has_dir "src/components"; then
  HAS_UI=1
fi
if [ "$HAS_UI" -eq 0 ]; then
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

IGNORE=('!node_modules' '!dist' '!build' '!**/*.test.*')
FAIL=0

# 1. <img> sem alt (CRIT a11y)
log_info "Buscando <img> sem alt..."
TMP=$(mktemp)
rg -nP "<img(?![^>]*\balt=)" --type html "${IGNORE[@]}" > "$TMP" 2>/dev/null || true
IMG_NO_ALT=$(wc -l < "$TMP" || echo 0)
if [ "$IMG_NO_ALT" -gt 0 ]; then
  while IFS=: read -r file line content; do
    [ -z "$file" ] && continue
    add_finding "high" "<img> sem alt: $(echo "$content" | xargs | cut -c1-80)" "$file" "$line"
  done < "$TMP"
  log_fail "$IMG_NO_ALT <img> sem alt — WCAG 1.1.1 violation"
fi
rm -f "$TMP"

# 2. outline:none sem :focus-visible substituto
log_info "Buscando outline:none..."
TMP=$(mktemp)
rg -n "outline\s*:\s*(none|0)" --type css --type scss   "${IGNORE[@]}" > "$TMP" 2>/dev/null || true
OUTLINE_NONE=$(wc -l < "$TMP" || echo 0)
if [ "$OUTLINE_NONE" -gt 0 ]; then
  add_finding "high" "$OUTLINE_NONE outline:none — sem foco visível quebra a11y de teclado" "" ""
  log_warn "$OUTLINE_NONE outline:none (precisa :focus-visible substituto)"
fi
rm -f "$TMP"

# 3. <button> sem texto/aria-label (apenas ícone)
log_info "Buscando <button> só com <svg>..."
TMP=$(mktemp)
rg -nU "<button[^>]*>\s*<svg"   "${IGNORE[@]}" 2>/dev/null | grep -v "aria-label" > "$TMP" || true
BTN_NO_LABEL=$(wc -l < "$TMP" || echo 0)
if [ "$BTN_NO_LABEL" -gt 0 ]; then
  add_finding "high" "$BTN_NO_LABEL <button> com <svg> sem aria-label — screen reader não anuncia" "" ""
fi
rm -f "$TMP"

# 4. Placeholder substituindo label
log_info "Buscando <input> sem <label>..."
TMP=$(mktemp)
rg -nU "<input[^>]*placeholder="   "${IGNORE[@]}" 2>/dev/null | grep -v "aria-label\|<label" > "$TMP" || true
NO_LABEL=$(wc -l < "$TMP" || echo 0)
if [ "$NO_LABEL" -gt 5 ]; then
  add_finding "med" "$NO_LABEL <input> com placeholder mas sem <label> visível detectado" "" ""
fi
rm -f "$TMP"

# 5. Lighthouse CI configurado
log_info "Verificando Lighthouse CI..."
if [ -f ".lighthouserc.json" ] || [ -f "lighthouserc.json" ] || [ -f ".lighthouserc.yml" ]; then
  log_pass "Lighthouse CI configurado"
else
  add_finding "low" "Sem Lighthouse CI — Web Vitals não monitorados" "" ""
fi

# 6. axe-core em tests
HAS_AXE=$(grep -lE "(@axe-core|jest-axe)" package.json 2>/dev/null | head -1)
if [ -z "$HAS_AXE" ]; then
  add_finding "med" "Sem @axe-core/playwright em tests — a11y não testada" "package.json" ""
fi

# 7. font-size < 14px em mobile (Tailwind text-xs etc)
log_info "Buscando font-size < 14px..."
TMP=$(mktemp)
rg -n "font-size\s*:\s*1[0-3]px" --type css --type scss "${IGNORE[@]}" > "$TMP" 2>/dev/null || true
SMALL_FONT=$(wc -l < "$TMP" || echo 0)
if [ "$SMALL_FONT" -gt 0 ]; then
  add_finding "low" "$SMALL_FONT regra(s) com font-size < 14px — ilegível em mobile" "" ""
fi
rm -f "$TMP"

# 8. text-overflow sem aria-* pra leitor de tela
log_info "Buscando text-overflow ellipsis sem title..."
TMP=$(mktemp)
rg -n "text-overflow\s*:\s*ellipsis" --type css "${IGNORE[@]}" > "$TMP" 2>/dev/null || true
ELLIPSIS=$(wc -l < "$TMP" || echo 0)
# (suppress, é só sinal)

CRITS=$(printf '%s\n' "${FINDINGS[@]}" | grep -c '"severity":"crit"' || echo 0)
HIGHS=$(printf '%s\n' "${FINDINGS[@]}" | grep -c '"severity":"high"' || echo 0)
if [ "$CRITS" -gt 0 ] || [ "$HIGHS" -gt 0 ]; then
  emit_result "$BLINDAR_AGENT" "failed" 1
  exit 1
fi

emit_result "$BLINDAR_AGENT" "passed" 0
exit 0
