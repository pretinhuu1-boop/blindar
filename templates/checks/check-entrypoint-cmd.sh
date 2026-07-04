#!/usr/bin/env bash
# Materializa: entrypoint-cmd — entrypoint que não honra o CMD. Bug real: entrypoint
# não fazia exec "$@" → o worker rodava o setup junto, PID 1 errado, race de seed.
BLINDAR_AGENT="check-entrypoint-cmd"
source "$(dirname "$0")/_lib.sh"
log_section "Check: entrypoint-cmd (entrypoint honra o CMD?)"

if ! command -v rg >/dev/null 2>&1; then emit_result "$BLINDAR_AGENT" "skipped" 0; exit 0; fi

# Acha entrypoints
ENTRYPOINTS=$(find . -maxdepth 3 \( -iname 'entrypoint*.sh' -o -iname 'docker-entrypoint*.sh' \) -not -path '*/node_modules/*' -not -path '*/.git/*' 2>/dev/null)
if [ -z "$ENTRYPOINTS" ]; then
  log_info "sem entrypoint script — skipped"; emit_result "$BLINDAR_AGENT" "skipped" 0; exit 0
fi
FAIL=0

for ep in $ENTRYPOINTS; do
  [ -f "$ep" ] || continue
  # Deve delegar ao CMD: exec "$@". Ignora linhas de comentário (evita match em doc).
  if ! grep -vE '^[[:space:]]*#' "$ep" 2>/dev/null | grep -qE 'exec[[:space:]]+"?\$@"?'; then
    add_finding "high" "entrypoint '$ep' não faz 'exec \"\$@\"' — não honra o CMD do Dockerfile/compose. Setup roda junto do processo principal, PID 1 errado, sinais não propagam" "$ep" ""
    FAIL=1
  fi
done

if [ "$FAIL" -eq 1 ]; then emit_result "$BLINDAR_AGENT" "failed" 1; exit 1; fi
emit_result "$BLINDAR_AGENT" "passed" 0
