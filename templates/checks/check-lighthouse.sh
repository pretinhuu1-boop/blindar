#!/usr/bin/env bash
# Lighthouse CI wrapper — Performance/A11y/Best Practices/SEO ≥ 90
# Requer: @lhci/cli instalado (npm i -D @lhci/cli)

BLINDAR_AGENT="check-lighthouse"
source "$(dirname "$0")/_lib.sh"

log_section "Check: Lighthouse CI (CWV + a11y + best-practices + SEO)"

if ! command -v npx >/dev/null 2>&1; then
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

# Verifica se @lhci/cli está instalado
if ! npx --no -- lhci --version >/dev/null 2>&1; then
  add_finding "med" "@lhci/cli não instalado — sem monitoramento de Web Vitals em CI" "package.json" ""
  log_warn "@lhci/cli ausente — instale: npm i -D @lhci/cli"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

# Verifica config
if [ ! -f ".lighthouserc.json" ] && [ ! -f ".lighthouserc.js" ] && [ ! -f ".lighthouserc.yml" ]; then
  add_finding "med" "Sem .lighthouserc.json — copie de blindar templates" "" ""
  log_warn "Sem .lighthouserc.json (use template do blindar)"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

# Roda autorun (assume URL configurada no rc ou via flag)
log_info "Rodando Lighthouse CI..."
TMP=$(mktemp -d)
if npx lhci autorun --upload.target=filesystem --upload.outputDir="$TMP" 2>&1; then
  log_pass "Lighthouse passou (>= thresholds configurados)"
  rm -rf "$TMP"
  emit_result "$BLINDAR_AGENT" "passed" 0
  exit 0
fi

# Parse falhas
if [ -f "$TMP/manifest.json" ]; then
  jq -c '.[]' "$TMP/manifest.json" 2>/dev/null | while read -r run; do
    url=$(echo "$run" | jq -r '.url')
    perf=$(echo "$run" | jq -r '.summary.performance // 0')
    a11y=$(echo "$run" | jq -r '.summary.accessibility // 0')
    bp=$(echo "$run" | jq -r '.summary["best-practices"] // 0')
    seo=$(echo "$run" | jq -r '.summary.seo // 0')
    add_finding "high" "Lighthouse $url: perf=$perf a11y=$a11y bp=$bp seo=$seo" "$url" ""
  done
fi

rm -rf "$TMP"
emit_result "$BLINDAR_AGENT" "failed" 1
exit 1
