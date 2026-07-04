#!/usr/bin/env bash
# Materializa agente: process-resilience
# Health endpoints, graceful shutdown, ulimits, deadlock retry

BLINDAR_AGENT="check-process-resilience"
source "$(dirname "$0")/_lib.sh"

log_section "Check: process-resilience (health + shutdown + backpressure + retry)"

if ! command -v rg >/dev/null 2>&1; then
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

# Roda só se for backend long-running
BACKEND=0
for lib in "@nestjs/core" express fastify "fastapi" "@fastify/cors"; do
  if grep -qE "\"$lib\":" package.json pyproject.toml 2>/dev/null; then
    BACKEND=1
  fi
done
if [ "$BACKEND" -eq 0 ]; then
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

IGNORE=(-g '!node_modules' -g '!dist' -g '!build' -g '!**/*.test.*')
FAIL=0

# 1. SIGTERM handler (graceful shutdown)
log_info "Verificando SIGTERM handler..."
HAS_SIGTERM=$(rg -l "process\.on\(['\"]SIGTERM" --type ts --type js "${IGNORE[@]}" 2>/dev/null | head -1)
if [ -z "$HAS_SIGTERM" ]; then
  add_finding "high" "Sem handler SIGTERM — K8s SIGKILL após 30s, perde requests em vôo" "" ""
  log_fail "Sem graceful shutdown"
fi

# 2. Health checks distintos (live vs ready)
HAS_LIVE=$(rg -l "(/health/live|/healthz/live)" --type ts --type js "${IGNORE[@]}" 2>/dev/null | head -1)
HAS_READY=$(rg -l "(/health/ready|/readyz)" --type ts --type js "${IGNORE[@]}" 2>/dev/null | head -1)
if [ -z "$HAS_LIVE" ] && [ -z "$HAS_READY" ]; then
  add_finding "high" "Sem /health/live nem /health/ready distintos" "" ""
elif [ -z "$HAS_LIVE" ]; then
  add_finding "med" "Sem /health/live separado de /ready (mistura conceitos)" "" ""
elif [ -z "$HAS_READY" ]; then
  add_finding "med" "Sem /health/ready separado de /live" "" ""
fi

# 3. Connection pool em DB
if is_prisma; then
  log_info "Verificando connection pool Prisma..."
  if ! grep -qE "connection_limit|pool_timeout" prisma/schema.prisma 2>/dev/null && \
     ! grep -qE "connection_limit" .env.example 2>/dev/null; then
    add_finding "med" "Prisma sem connection_limit configurado — pode saturar DB em scale" "" ""
  fi
fi

# 4. Cache infinito (new Map() sem TTL)
log_info "Buscando caches unbounded..."
TMP=$(mktemp)
rg -n "new Map\(\)" --type ts --type js "${IGNORE[@]}" -A 5 2>/dev/null | grep -B 5 "set\(" | grep "new Map" > "$TMP" || true
UNBOUNDED=$(wc -l < "$TMP" || echo 0)
if [ "$UNBOUNDED" -gt 3 ]; then
  add_finding "med" "$UNBOUNDED uso(s) de new Map() — verificar se há TTL/LRU pra evitar OOM" "" ""
fi
rm -f "$TMP"

# 5. Deadlock retry handler (Postgres 40001 / 40P01)
log_info "Verificando deadlock retry..."
if is_prisma; then
  HAS_RETRY=$(rg -l "(40001|40P01|deadlock.*retry|withDeadlockRetry)" --type ts "${IGNORE[@]}" 2>/dev/null | head -1)
  if [ -z "$HAS_RETRY" ]; then
    add_finding "low" "Sem deadlock retry detectado (Postgres 40001/40P01) — erros 500 desnecessários" "" ""
  fi
fi

# 6. Event loop lag monitor
HAS_EVENT_LAG=$(rg -l "monitorEventLoopDelay|perf_hooks" --type ts --type js "${IGNORE[@]}" 2>/dev/null | head -1)
if [ -z "$HAS_EVENT_LAG" ]; then
  add_finding "low" "Sem monitor de event loop lag — backpressure invisível" "" ""
fi

# 7. Long-running transaction protection
if is_prisma; then
  if ! grep -qE "statement_timeout|idle_in_transaction" .env.example prisma/schema.prisma 2>/dev/null; then
    add_finding "med" "Sem statement_timeout configurado — query travada satura DB" "" ""
  fi
fi

# 8. ulimit / container memory limit (procura em k8s/docker)
if [ -f "Dockerfile" ]; then
  if ! grep -qE "(ulimit|--max-old-space-size)" Dockerfile 2>/dev/null; then
    add_finding "low" "Dockerfile sem --max-old-space-size — Node V8 escolhe heap automático" "Dockerfile" ""
  fi
fi

if [ -d "k8s" ] || [ -d ".k8s" ] || ls -1 *.yaml 2>/dev/null | grep -qE "deployment|statefulset"; then
  K8S_FILES=$(find . -maxdepth 3 -name "deployment.yaml" -o -name "statefulset.yaml" 2>/dev/null | grep -v node_modules | head -5)
  for f in $K8S_FILES; do
    if ! grep -qE "resources:\s*$|memory:" "$f" 2>/dev/null; then
      add_finding "med" "K8s manifest sem resources.limits.memory — risco OOM cluster-wide" "$f" ""
    fi
  done
fi

if [ "$FAIL" -eq 1 ]; then
  emit_result "$BLINDAR_AGENT" "failed" 1
  exit 1
fi

emit_result "$BLINDAR_AGENT" "passed" 0
exit 0
