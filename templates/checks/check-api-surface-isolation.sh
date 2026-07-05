#!/usr/bin/env bash
# Materializa: api-surface-isolation — API INTERNA nunca aceita chamada externa;
# API EXTERNA com proteção total. Usa o grafo (surface.external × surface.internal).
BLINDAR_AGENT="check-api-surface-isolation"
source "$(dirname "$0")/_lib.sh"
log_section "Check: api-surface-isolation (interna×externa)"

if ! command -v rg >/dev/null 2>&1; then emit_result "$BLINDAR_AGENT" "skipped" 0; exit 0; fi
IGNORE=(-g '!node_modules' -g '!dist' -g '!.git' -g '!**/*.test.*')
load_intelligence_globs "$BLINDAR_AGENT"
FAIL=0

# Garante o grafo (reusa Fase 1; constrói se faltar)
GRAPH=".blindar/graph.json"
if [ ! -f "$GRAPH" ] && command -v node >/dev/null 2>&1; then
  GB="$(dirname "$0")/../../scripts/graph-build.js"
  [ -f "$GB" ] && node "$GB" --dir . >/dev/null 2>&1 || true
fi

# 1. Serviço interno (db/redis/mq/worker) com porta publicada = aceita externa (CRIT)
if [ -f "$GRAPH" ] && command -v node >/dev/null 2>&1; then
  EXPOSED_INTERNAL=$(node -e "
    try{const g=require('./.blindar/graph.json');
    const bad=g.nodes.filter(n=>n.type==='service'&&n.exposed&&/^(db|database|postgres|postgresql|mysql|mariadb|mongo|mongodb|redis|memcached|rabbitmq|kafka|zookeeper|elasticsearch|internal|worker|queue)/i.test(n.name||''));
    process.stdout.write(bad.map(n=>n.name).join(','));}catch(e){}" 2>/dev/null)
  if [ -n "$EXPOSED_INTERNAL" ]; then
    add_finding "crit" "Serviço interno com porta publicada no host: $EXPOSED_INTERNAL — db/redis/worker não devem aceitar chamada externa. Remova 'ports:', use rede interna do compose." "" ""
    FAIL=1
  fi
fi

# 2. API interna com bind em 0.0.0.0 (todas as interfaces) (CRIT)
BIND_ALL=$(rg -l "0\.0\.0\.0" --type ts --type js --type py "${IGNORE[@]}" "${INTEL_GLOBS[@]}" 2>/dev/null | grep -iE "internal|rpc|worker|admin" | wc -l)
if [ "$BIND_ALL" -gt 0 ]; then
  add_finding "crit" "API interna faz bind em 0.0.0.0 (todas interfaces) — restrinja a 127.0.0.1/rede interna" "" ""
  FAIL=1
fi

# 3. Endpoints externos (POST/PUT/PATCH) sem validação de schema de input (HIGH)
HAS_WRITE=$(rg -c "(app|router|fastify)\.(post|put|patch)\(|@(Post|Put|Patch)\(" --type ts --type js "${IGNORE[@]}" "${INTEL_GLOBS[@]}" 2>/dev/null | wc -l)
HAS_VALIDATION=$(rg -c "(zod|z\.object|joi|yup|class-validator|@IsString|@IsNotEmpty|pydantic|BaseModel|ajv|express-validator|valibot)" --type ts --type js --type py "${IGNORE[@]}" "${INTEL_GLOBS[@]}" 2>/dev/null | wc -l)
if [ "$HAS_WRITE" -gt 0 ] && [ "$HAS_VALIDATION" -eq 0 ]; then
  add_finding "high" "Endpoints externos de escrita sem validação de schema de input (zod/joi/pydantic/class-validator) — superfície externa deve validar TODO input" "" ""
  FAIL=1
fi

# 4. Endpoints externos sem nenhuma proteção de rate-limit/WAF (HIGH, defesa em profundidade)
HAS_EXTERNAL_EP=$(rg -c "(app|router|fastify)\.(get|post|put|delete|patch)\(" --type ts --type js "${IGNORE[@]}" "${INTEL_GLOBS[@]}" 2>/dev/null | wc -l)
HAS_EDGE_PROTECT=$(rg -c "(rate-limit|rateLimit|@nestjs/throttler|helmet|@upstash/ratelimit|cloudflare|waf|mod_security)" --type ts --type js --type json "${IGNORE[@]}" "${INTEL_GLOBS[@]}" 2>/dev/null | wc -l)
if [ "$HAS_EXTERNAL_EP" -gt 0 ] && [ "$HAS_EDGE_PROTECT" -eq 0 ]; then
  add_finding "high" "Superfície externa sem rate-limit/WAF/helmet — externa precisa de proteção de borda contra abuso/DoS" "" ""
  FAIL=1
fi

[ "$FAIL" -eq 1 ] && { emit_result "$BLINDAR_AGENT" "failed" 1; exit 1; }
emit_result "$BLINDAR_AGENT" "passed" 0
