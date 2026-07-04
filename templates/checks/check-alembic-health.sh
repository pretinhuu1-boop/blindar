#!/usr/bin/env bash
# Materializa: alembic-health — env.py importa models + script.py.mako existe +
# target_metadata setado. Bug real: env.py não importava models e faltava
# script.py.mako → autogenerate quebrado (migrations vazias).
BLINDAR_AGENT="check-alembic-health"
source "$(dirname "$0")/_lib.sh"
log_section "Check: alembic-health"

ENVPY=$(ls alembic/env.py migrations/env.py */alembic/env.py */migrations/env.py 2>/dev/null | head -1)
if [ -z "$ENVPY" ]; then
  log_info "sem alembic/env.py — skipped"; emit_result "$BLINDAR_AGENT" "skipped" 0; exit 0
fi
FAIL=0
ALEMBIC_DIR=$(dirname "$ENVPY")

# 1. script.py.mako presente (sem ele, `alembic revision` quebra)
if [ ! -f "$ALEMBIC_DIR/script.py.mako" ]; then
  add_finding "high" "Falta $ALEMBIC_DIR/script.py.mako — 'alembic revision' quebra sem o template" "$ALEMBIC_DIR" ""
  FAIL=1
fi

# 2. target_metadata = None → autogenerate não detecta nada
if grep -qE "target_metadata[[:space:]]*=[[:space:]]*None" "$ENVPY" 2>/dev/null; then
  add_finding "high" "target_metadata=None em env.py — autogenerate gera migration vazia (não detecta mudanças de schema)" "$ENVPY" ""
  FAIL=1
fi

# 3. env.py importa os models (Base.metadata)?
if ! grep -qE "(import.*models|from .*import .*Base|Base\.metadata|SQLModel\.metadata|import_module)" "$ENVPY" 2>/dev/null; then
  add_finding "med" "env.py não parece importar os models (Base.metadata) — autogenerate não vê as tabelas" "$ENVPY" ""
fi

if [ "$FAIL" -eq 1 ]; then emit_result "$BLINDAR_AGENT" "failed" 1; exit 1; fi
[ "${#FINDINGS[@]}" -gt 0 ] && { emit_result "$BLINDAR_AGENT" "failed" 1; exit 0; }
emit_result "$BLINDAR_AGENT" "passed" 0
