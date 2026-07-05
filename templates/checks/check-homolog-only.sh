#!/usr/bin/env bash
# Materializa: homolog-only — proíbe config de DEV no artefato deployável.
# Regra do usuário: simulação/homologação sempre com dados MOCK direto no banco,
# espelho de produção. NUNCA "dev" (nem NODE_ENV=development, nem dev server,
# nem DB de dev, nem --reload/--debug no entrypoint de produção).
BLINDAR_AGENT="check-homolog-only"
source "$(dirname "$0")/_lib.sh"
log_section "Check: homolog-only (sem config de dev no deploy)"

if ! command -v rg >/dev/null 2>&1; then emit_result "$BLINDAR_AGENT" "skipped" 0; exit 0; fi

# Só faz sentido se houver artefato deployável
DEPLOY_FILES=""
for f in Dockerfile docker-compose.yml docker-compose.yaml compose.yml compose.yaml Procfile; do
  [ -f "$f" ] && DEPLOY_FILES="yes"
done
if [ -z "$DEPLOY_FILES" ] && ! ls .env.production .env.homolog >/dev/null 2>&1; then
  log_info "Sem Dockerfile/compose/Procfile — nada de deploy pra checar — skipped"
  emit_result "$BLINDAR_AGENT" "skipped" 0; exit 0
fi

IGNORE=(-g '!node_modules' -g '!dist' -g '!.git' -g '!**/*.test.*')
load_intelligence_globs "$BLINDAR_AGENT"
FAIL=0

# 1. NODE_ENV=development no artefato de deploy (CRIT)
DEV_ENV=$(rg -c "NODE_ENV[[:space:]=:'\"]+development" Dockerfile* docker-compose*.y*ml compose*.y*ml Procfile 2>/dev/null | wc -l)
if [ "$DEV_ENV" -gt 0 ]; then
  add_finding "crit" "NODE_ENV=development no artefato deployável — homolog/prod nunca roda em dev" "" ""
  FAIL=1
fi

# 2. Dev server / hot-reload no entrypoint de produção (HIGH)
DEV_SERVER=$(rg -c "(nodemon|ts-node-dev|next[[:space:]]+dev|npm[[:space:]]+run[[:space:]]+dev|yarn[[:space:]]+dev|pnpm[[:space:]]+dev|vite[[:space:]]*$|flask[[:space:]]+run|uvicorn.*--reload|FLASK_DEBUG|--inspect)" Dockerfile* docker-compose*.y*ml compose*.y*ml Procfile 2>/dev/null | wc -l)
if [ "$DEV_SERVER" -gt 0 ]; then
  add_finding "high" "Dev server / hot-reload (nodemon/next dev/--reload/flask run) no deploy — usar build de produção" "" ""
  FAIL=1
fi

# 3. DEBUG=True / debug=true no deploy (HIGH)
DEBUG_ON=$(rg -c "(DEBUG[[:space:]=:'\"]+([Tt]rue|1)|debug[[:space:]]*=[[:space:]]*[Tt]rue)" Dockerfile* docker-compose*.y*ml compose*.y*ml .env.production .env.homolog 2>/dev/null | wc -l)
if [ "$DEBUG_ON" -gt 0 ]; then
  add_finding "high" "DEBUG=true no artefato de deploy — desliga em homolog/produção" "" ""
  FAIL=1
fi

# 4. DB de dev (sqlite :memory: / dev.db) em compose/env de deploy (MED)
DEV_DB=$(rg -c "(:memory:|sqlite:///?(dev|test)|dev\.db|localhost/.*_dev)" docker-compose*.y*ml compose*.y*ml .env.production .env.homolog 2>/dev/null | wc -l)
if [ "$DEV_DB" -gt 0 ]; then
  add_finding "med" "Banco de dev (sqlite/:memory:/_dev) no deploy — homolog espelha produção com dados mock no banco real" "" ""
fi

if [ "$FAIL" -eq 1 ]; then emit_result "$BLINDAR_AGENT" "failed" 1; exit 1; fi
emit_result "$BLINDAR_AGENT" "passed" 0
exit 0
