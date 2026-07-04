#!/usr/bin/env bash
# Materializa: govtech-acessibilidade (eMAG, ePING, gov.br, LAI, VLibras)
BLINDAR_AGENT="check-govtech-acessibilidade"
source "$(dirname "$0")/_lib.sh"
log_section "Check: Govtech & Acessibilidade BR (eMAG/gov.br/LAI)"

if ! command -v rg >/dev/null 2>&1; then emit_result "$BLINDAR_AGENT" "skipped" 0; exit 0; fi

IGNORE=(-g '!node_modules' -g '!dist' -g '!build' -g '!.next' -g '!coverage' -g '!**/*.test.*' -g '!**/*.spec.*')

# ─── Gate: só roda se detectar indícios de gov BR ───
GOV_HITS=0
GOV_HITS=$(( GOV_HITS + $(rg -c "gov\\.br" --type ts --type tsx --type js --type html --type json "${IGNORE[@]}" 2>/dev/null | wc -l || echo 0) ))
GOV_HITS=$(( GOV_HITS + $(rg -c "vlibras" --type ts --type tsx --type js --type html "${IGNORE[@]}" 2>/dev/null | wc -l || echo 0) ))
GOV_HITS=$(( GOV_HITS + $(rg -c "(lei.de.acesso|\\bLAI\\b|transparencia)" --type ts --type tsx --type md "${IGNORE[@]}" 2>/dev/null | wc -l || echo 0) ))
GOV_HITS=$(( GOV_HITS + $(rg -c "(eMAG|emag)" --type ts --type tsx --type md --type html "${IGNORE[@]}" 2>/dev/null | wc -l || echo 0) ))
GOV_HITS=$(( GOV_HITS + $(rg -c "(prefeitura|ministerio|secretaria.*?estado|tribunal|camara.*?municipal)" --type ts --type tsx --type md "${IGNORE[@]}" 2>/dev/null | wc -l || echo 0) ))

if [ "$GOV_HITS" -eq 0 ]; then
  log_warn "Nenhum indício de govtech BR detectado — pulando"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

log_info "Indícios de govtech BR detectados ($GOV_HITS sinais) — auditando"

# ─── 1. Login não-gov.br como única opção (CRIT pra sistema público) ───
LOGIN_HITS=$(rg -c "(login|signin|sign-in|signIn|auth/login)" --type ts --type tsx "${IGNORE[@]}" 2>/dev/null | wc -l || echo 0)
GOVBR_LOGIN=$(rg -c "(gov\\.br|govbr|acesso\\.gov|sso\\.acesso)" --type ts --type tsx --type js --type json "${IGNORE[@]}" 2>/dev/null | wc -l || echo 0)
if [ "$LOGIN_HITS" -gt 3 ] && [ "$GOVBR_LOGIN" -eq 0 ]; then
  add_finding "critical" "Sistema com login mas sem opção gov.br SSO — diretriz federal exige aceite de identidade cidadã" "" ""
fi

# ─── 2. Sem botão "Acessibilidade" no header (HIGH — eMAG 1.10) ───
ACCESS_BTN=$(rg -c "(acessibilidade|accessibility-?menu|a11y-?menu)" --type tsx --type html --type ts "${IGNORE[@]}" 2>/dev/null | wc -l || echo 0)
if [ "$ACCESS_BTN" -eq 0 ]; then
  add_finding "high" "Sem botão/menu 'Acessibilidade' visível — viola eMAG 1.10" "" ""
fi

# ─── 3. Sem atalhos de teclado eMAG 1.3 (Alt+1=conteudo, Alt+2=menu, Alt+3=busca) (HIGH) ───
ACCESSKEY_HITS=$(rg -c "(accesskey|accessKey)" --type tsx --type html "${IGNORE[@]}" 2>/dev/null | wc -l || echo 0)
ALT_SHORTCUTS=$(rg -c "(Alt\\+1|alt\\+1|altKey.*?key.*?[1-4])" --type ts --type tsx "${IGNORE[@]}" 2>/dev/null | wc -l || echo 0)
if [ "$ACCESSKEY_HITS" -eq 0 ] && [ "$ALT_SHORTCUTS" -eq 0 ]; then
  add_finding "high" "Sem atalhos Alt+1/2/3/4 (conteúdo, menu, busca, rodapé) — viola eMAG 1.3" "" ""
fi

# ─── 4. outline:none sem substituto = sem foco visual (CRIT — eMAG 2.1) ───
OUTLINE_NONE=$(rg -nU ":focus[\\s\\S]{0,200}outline\\s*:\\s*(none|0)" --type css --type scss --type tsx --type ts "${IGNORE[@]}" 2>/dev/null | wc -l || echo 0)
FOCUS_VISIBLE=$(rg -c "(focus-visible|focusVisible|outline:\\s*[12]px)" --type css --type scss --type tsx --type ts "${IGNORE[@]}" 2>/dev/null | wc -l || echo 0)
if [ "$OUTLINE_NONE" -gt 0 ] && [ "$FOCUS_VISIBLE" -eq 0 ]; then
  add_finding "critical" "$OUTLINE_NONE regra(s) ':focus { outline:none }' sem substituto visual — viola eMAG 2.1 + WCAG 2.4.7" "" ""
fi

# ─── 5. Sem versão alto-contraste (HIGH — eMAG 4.4) ───
HIGH_CONTRAST=$(rg -c "(alto-?contraste|high-?contrast|highContrast|contrast-mode)" --type ts --type tsx --type css --type scss "${IGNORE[@]}" 2>/dev/null | wc -l || echo 0)
if [ "$HIGH_CONTRAST" -eq 0 ]; then
  add_finding "high" "Sem versão de alto contraste — viola eMAG 4.4" "" ""
fi

# ─── 6. Mapa do site ausente (MED — eMAG 1.5) ───
SITEMAP_LINK=$(rg -c "(mapa[- ]?do[- ]?site|site-?map|sitemap)" --type tsx --type html --type ts "${IGNORE[@]}" 2>/dev/null | wc -l || echo 0)
if [ "$SITEMAP_LINK" -eq 0 ]; then
  add_finding "medium" "Sem link 'Mapa do site' (rodapé) — viola eMAG 1.5" "" ""
fi

# ─── 7. Sem lang="pt-br" em <html> (HIGH) ───
HTML_TAGS_TMP=$(mktemp 2>/dev/null || echo "/tmp/blindar-html.$$")
rg -n "<html" --type tsx --type html "${IGNORE[@]}" 2>/dev/null > "$HTML_TAGS_TMP" || true
HTML_TOTAL=$(wc -l < "$HTML_TAGS_TMP" 2>/dev/null || echo 0)
HTML_NO_LANG=0
if [ "$HTML_TOTAL" -gt 0 ]; then
  HTML_NO_LANG=$(rg -vc '(lang="pt-br"|lang="pt-BR"|lang=\{"pt-br"\}|lang=\{"pt-BR"\})' "$HTML_TAGS_TMP" 2>/dev/null || echo 0)
fi
rm -f "$HTML_TAGS_TMP"
if [ "$HTML_NO_LANG" -gt 0 ]; then
  add_finding "high" "$HTML_NO_LANG tag(s) <html> sem lang=\"pt-br\" — viola eMAG 3.1 + WCAG 3.1.1" "" ""
fi

# ─── 8. Documentos públicos em PDF não-acessível/imagem (HIGH) ───
PDF_COUNT=0
if command -v find >/dev/null 2>&1; then
  PDF_COUNT=$(find . -maxdepth 6 -name "*.pdf" -not -path "*/node_modules/*" -not -path "*/.next/*" -not -path "*/dist/*" 2>/dev/null | wc -l || echo 0)
fi
HTML_ALT_DOC=$(rg -c "\\.(odt|html)\"" --type tsx --type html --type ts "${IGNORE[@]}" 2>/dev/null | wc -l || echo 0)
if [ "$PDF_COUNT" -gt 0 ] && [ "$HTML_ALT_DOC" -eq 0 ]; then
  add_finding "high" "$PDF_COUNT PDF(s) público(s) detectado(s) sem alternativa em HTML/ODT — exclui usuários e viola eMAG 5.5 + LAI" "" ""
fi

# ─── 9. LAI: ausência de /transparencia OU /dados-abertos (MED se for órgão público) ───
TRANSP_PAGE=$(rg -c "(/transparencia|/dados-abertos|transparencia-ativa)" --type tsx --type ts --type js "${IGNORE[@]}" 2>/dev/null | wc -l || echo 0)
PUBLIC_ORG=$(rg -c "(prefeitura|ministerio|secretaria.*?estado|tribunal|camara.*?municipal|orgao.*?publico)" --type ts --type tsx --type md "${IGNORE[@]}" 2>/dev/null | wc -l || echo 0)
if [ "$PUBLIC_ORG" -gt 0 ] && [ "$TRANSP_PAGE" -eq 0 ]; then
  add_finding "medium" "Órgão público sem página /transparencia ou /dados-abertos — viola LAI (Lei 12.527/2011)" "" ""
fi

# ─── 10. CSP que bloqueia ferramentas de leitor (MED) ───
CSP_HITS_TMP=$(mktemp 2>/dev/null || echo "/tmp/blindar-csp.$$")
rg -nU "Content-Security-Policy" --type ts --type tsx --type js --type json --type html "${IGNORE[@]}" -A 5 2>/dev/null > "$CSP_HITS_TMP" || true
CSP_BLOCKS_GOV=0
if [ -s "$CSP_HITS_TMP" ]; then
  CSP_HAS_VLIBRAS=$(rg -c "vlibras\\.gov\\.br" "$CSP_HITS_TMP" 2>/dev/null || echo 0)
  CSP_HAS_GOVBR=$(rg -c "(sso\\.acesso\\.gov|www\\.gov\\.br)" "$CSP_HITS_TMP" 2>/dev/null || echo 0)
  if [ "$CSP_HAS_VLIBRAS" -eq 0 ] && [ "$CSP_HAS_GOVBR" -eq 0 ]; then
    CSP_BLOCKS_GOV=1
  fi
fi
rm -f "$CSP_HITS_TMP"
if [ "$CSP_BLOCKS_GOV" -gt 0 ]; then
  add_finding "medium" "CSP não permite vlibras.gov.br / sso.acesso.gov.br — pode bloquear leitor de tela + login gov.br" "" ""
fi

# ─── 11. VLibras não embedado (MED — recomendado pra gov) ───
VLIBRAS_EMBED=$(rg -c "(vlibras\\.gov\\.br/app|VLibras\\.Widget|vw-access-button)" --type tsx --type html --type js --type ts "${IGNORE[@]}" 2>/dev/null | wc -l || echo 0)
if [ "$VLIBRAS_EMBED" -eq 0 ]; then
  add_finding "medium" "VLibras não embedado — recomendado pelo MCom em portais gov BR (acessibilidade Libras)" "" ""
fi

# ─── Resultado ───
CRIT_COUNT=$(printf '%s\n' "${FINDINGS[@]:-}" | grep -c '"severity":"critical"' 2>/dev/null || echo 0)
HIGH_COUNT=$(printf '%s\n' "${FINDINGS[@]:-}" | grep -c '"severity":"high"' 2>/dev/null || echo 0)

if [ "${#FINDINGS[@]}" -eq 0 ]; then
  emit_result "$BLINDAR_AGENT" "passed" 0
  exit 0
fi

if [ "$CRIT_COUNT" -gt 0 ] || [ "$HIGH_COUNT" -gt 2 ]; then
  emit_result "$BLINDAR_AGENT" "failed" 1
  exit 1
fi

emit_result "$BLINDAR_AGENT" "passed" 0
