#!/usr/bin/env bash
# Materializa: redis-patterns
BLINDAR_AGENT="check-redis-patterns"
source "$(dirname "$0")/_lib.sh"
log_section "Check: redis-patterns (TTL + tenant prefix + eviction + Redlock)"

if ! command -v rg >/dev/null 2>&1; then emit_result "$BLINDAR_AGENT" "skipped" 0; exit 0; fi

# Detecta Redis
HAS_REDIS=0
for lib in redis ioredis "@nestjs/cache-manager" bullmq; do
  grep -qE "\"$lib\":" package.json 2>/dev/null && HAS_REDIS=1
done
[ "$HAS_REDIS" -eq 0 ] && grep -qE "redis|valkey" docker-compose.yml 2>/dev/null && HAS_REDIS=1

if [ "$HAS_REDIS" -eq 0 ]; then emit_result "$BLINDAR_AGENT" "skipped" 0; exit 0; fi

IGNORE=('!node_modules' '!dist' '!**/*.test.*')
FAIL=0

# 1. Chave sem TTL (memory leak)
log_info "Buscando redis.set sem TTL..."
TMP=$(mktemp)
rg -nE "redis\.(set|hset|sadd|zadd)\(" --type ts --type js "${IGNORE[@]}" 2>/dev/null | \
  grep -v "(EX:|PX:|EXAT:|setEx|setex|SETEX|expire|@blindar:redis-keep|EXPIRE)" > "$TMP" || true
NO_TTL=$(wc -l < "$TMP" || echo 0)
if [ "$NO_TTL" -gt 0 ]; then
  while IFS=: read -r file line content; do
    [ -z "$file" ] && continue
    add_finding "high" "Redis SET sem TTL (memory leak): $(echo "$content" | xargs | cut -c1-80)" "$file" "$line"
  done < "$TMP"
  log_fail "$NO_TTL chave(s) sem TTL"
  FAIL=1
fi
rm -f "$TMP"

# 2. SETNX cru (race condition)
log_info "Buscando SETNX sem Redlock..."
TMP=$(mktemp)
rg -niE "(setnx|setNX)\(" --type ts --type js "${IGNORE[@]}" 2>/dev/null | grep -v "redlock" > "$TMP" || true
SETNX_RAW=$(wc -l < "$TMP" || echo 0)
if [ "$SETNX_RAW" -gt 0 ]; then
  add_finding "high" "$SETNX_RAW SETNX cru — usar Redlock pra distributed lock" "" ""
  log_warn "SETNX cru detectado"
fi
rm -f "$TMP"

# 3. Multi-tenant sem prefix
IS_MULTITENANT=0
grep -lE "tenantId|tenant_id" prisma/schema.prisma 2>/dev/null | head -1 | grep -q . && IS_MULTITENANT=1

if [ "$IS_MULTITENANT" -eq 1 ]; then
  log_info "Buscando keys Redis sem tenant prefix..."
  TMP=$(mktemp)
  rg -nE "redis\.(get|set|hget|hset|del)\(['\"][^t]" --type ts --type js "${IGNORE[@]}" 2>/dev/null | \
    grep -v "tenant:" | grep -v "@blindar:redis-keep" > "$TMP" || true
  NO_PREFIX=$(wc -l < "$TMP" || echo 0)
  if [ "$NO_PREFIX" -gt 5 ]; then
    add_finding "high" "$NO_PREFIX redis op em projeto multi-tenant sem prefix 'tenant:'" "" ""
  fi
  rm -f "$TMP"
fi

# 4. noeviction em config (CRIT)
NOEVICT=$(grep -rE "maxmemory-policy.*noeviction" docker-compose.yml redis.conf k8s/ 2>/dev/null | wc -l || echo 0)
if [ "$NOEVICT" -gt 0 ]; then
  add_finding "crit" "maxmemory-policy=noeviction em cache prod — OOM bloqueia escritas" "" ""
  FAIL=1
fi

# 5. AUTH ausente em prod
TMP=$(mktemp)
rg -n "new Redis\(\{|new IORedis\(\{" --type ts "${IGNORE[@]}" -A 5 2>/dev/null | grep -v "password\|@blindar:keep" > "$TMP" || true
NO_AUTH=$(grep -c "new Redis\|new IORedis" "$TMP" 2>/dev/null || echo 0)
if [ "$NO_AUTH" -gt 0 ]; then
  add_finding "high" "$NO_AUTH conexão Redis sem password — exigir REDIS_PASSWORD em prod" "" ""
fi
rm -f "$TMP"

# 6. KEYS * em código (bloqueia Redis)
KEYS_STAR=$(rg -cE "redis\.keys\(['\"]\*" --type ts --type js "${IGNORE[@]}" 2>/dev/null | wc -l || echo 0)
if [ "$KEYS_STAR" -gt 0 ]; then
  add_finding "high" "$KEYS_STAR uso(s) de KEYS * — bloqueia Redis. Usar SCAN" "" ""
fi

# 7. FLUSHALL em código (destrutivo)
FLUSH=$(rg -ciE "flushall|flushdb" --type ts --type js "${IGNORE[@]}" 2>/dev/null | wc -l || echo 0)
if [ "$FLUSH" -gt 0 ]; then
  add_finding "med" "$FLUSH uso(s) de FLUSHALL/FLUSHDB — apaga tudo, revisar urgente" "" ""
fi

# 8. Pipeline em loop com N round-trips
LOOP_ROUNDTRIPS=$(rg -nE "for.*\{[^}]*await redis\." --type ts "${IGNORE[@]}" 2>/dev/null | wc -l || echo 0)
[ "$LOOP_ROUNDTRIPS" -gt 3 ] && add_finding "med" "$LOOP_ROUNDTRIPS loop com await redis dentro — usar pipeline" "" ""

if [ "$FAIL" -eq 1 ]; then
  emit_result "$BLINDAR_AGENT" "failed" 1
  exit 1
fi

emit_result "$BLINDAR_AGENT" "passed" 0
exit 0
