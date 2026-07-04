#!/usr/bin/env bash
# Materializa: deps-sync — Dockerfile instalando deps em lista fixa dessincroniza
# do manifesto (pyproject/requirements/package.json). Bug real: faltava slowapi/
# anthropic/otel no Dockerfile → ModuleNotFoundError, imagem não boota.
BLINDAR_AGENT="check-deps-sync"
source "$(dirname "$0")/_lib.sh"
log_section "Check: deps-sync (Dockerfile ↔ manifesto)"

if ! command -v rg >/dev/null 2>&1; then emit_result "$BLINDAR_AGENT" "skipped" 0; exit 0; fi
DOCKERFILES=$(find . -maxdepth 3 -iname 'Dockerfile*' -not -path '*/node_modules/*' -not -path '*/.git/*' 2>/dev/null)
[ -z "$DOCKERFILES" ] && { log_info "sem Dockerfile — skipped"; emit_result "$BLINDAR_AGENT" "skipped" 0; exit 0; }
FAIL=0

# pip install com lista fixa de pacotes (não -r, não ., não poetry)
PIP_HARD=$(rg -n "pip3? install " $DOCKERFILES 2>/dev/null | grep -viE "(-r |requirements|--upgrade|poetry|pip install +\.)" | grep -iE "install +[a-z0-9_.-]+" | wc -l)
if [ "$PIP_HARD" -gt 0 ]; then
  add_finding "high" "Dockerfile instala pip em lista fixa de pacotes — dessincroniza do pyproject/requirements (faltar 1 dep = ModuleNotFoundError, imagem não boota). Use 'pip install -r requirements.txt' ou 'poetry install'" "Dockerfile" ""
  FAIL=1
fi

# npm install com pacotes nomeados (não npm ci / npm install puro)
NPM_HARD=$(rg -n "npm (install|add|i) +[@a-z]" $DOCKERFILES 2>/dev/null | grep -viE "(npm install *&|npm ci|npm install *$|npm install --production|package)" | wc -l)
if [ "$NPM_HARD" -gt 0 ]; then
  add_finding "high" "Dockerfile instala npm com pacotes nomeados — use 'npm ci' (lockfile) pra não dessincronizar do package.json" "Dockerfile" ""
  FAIL=1
fi

if [ "$FAIL" -eq 1 ]; then emit_result "$BLINDAR_AGENT" "failed" 1; exit 1; fi
emit_result "$BLINDAR_AGENT" "passed" 0
