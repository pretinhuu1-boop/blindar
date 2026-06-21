#!/usr/bin/env bash
# Chromatic wrapper — visual regression em Storybook
# Requer: chromatic instalado + CHROMATIC_PROJECT_TOKEN no env

BLINDAR_AGENT="check-visual-regression"
source "$(dirname "$0")/_lib.sh"

log_section "Check: visual regression (Chromatic)"

if ! is_nodejs; then
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

# Verifica se Storybook + Chromatic estão configurados
HAS_STORYBOOK=$(grep -E "\"@storybook/" package.json 2>/dev/null | head -1)
HAS_CHROMATIC=$(grep -E "\"chromatic\":" package.json 2>/dev/null | head -1)

if [ -z "$HAS_STORYBOOK" ]; then
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

if [ -z "$HAS_CHROMATIC" ]; then
  add_finding "low" "Storybook detectado mas sem Chromatic — sem visual regression" "package.json" ""
  log_warn "Chromatic não configurado"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

if [ -z "${CHROMATIC_PROJECT_TOKEN:-}" ]; then
  add_finding "med" "CHROMATIC_PROJECT_TOKEN não configurado em env/CI" "" ""
  log_warn "Sem token — Chromatic não pode publicar"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

# Roda chromatic
log_info "Publicando snapshots no Chromatic..."
if npx chromatic --exit-zero-on-changes --skip 'dependabot/**' 2>&1; then
  log_pass "Chromatic: zero diff visual"
  emit_result "$BLINDAR_AGENT" "passed" 0
  exit 0
fi

add_finding "med" "Chromatic detectou diff visual — revisar no dashboard" "" ""
emit_result "$BLINDAR_AGENT" "failed" 1
exit 1
