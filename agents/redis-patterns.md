---
name: redis-patterns
category: performance
module: 9
priority: P1
description: |
  Redis/Valkey correto em produção: chaves sempre com TTL, multi-tenant
  via prefix, eviction policy adequada, persistence (RDB+AOF), Redlock
  para distributed lock, pipeline pra evitar N round-trips, cluster mode
  > 25GB, Streams com consumer groups + XAUTOCLAIM, connection pool com
  TLS+AUTH em prod, observability (slow log, hit rate, evictions).
---

# Agent: redis-patterns

## Missão

Redis bem usado é cache que voa. Mal usado é memory leak (chaves sem
TTL), data loss em crash (RDB sem AOF), SPOF (single instance), race
conditions (`SETNX` cru em vez de Redlock). Este agente garante que
Redis no projeto segue patterns 2026.

## Quando rodar

- Módulo 9 selecionado
- Detectado: `redis`, `ioredis`, `bullmq` (que usa Redis), `@nestjs/cache-manager`
- Operador pediu "cache", "Redis", "Valkey", "rate limit"

## A. Decisão: Redis vs Valkey vs alternativas

| Engine | Quando |
|---|---|
| **Redis** (Redis Labs) | Default. Maturidade. Licença Source-Available desde 2024 |
| **Valkey** (Linux Foundation fork) | Se quer 100% OSS / evita licença comercial Redis |
| **DragonflyDB** | Drop-in, 25x mais rápido em alguns workloads, single-process |
| **KeyDB** | Multi-threaded Redis-compatible |
| **Memcached** | NÃO. Sem persistence, sem types, sem streams. Use Redis. |
| **Hazelcast / Coherence** | Enterprise Java, overkill pra maioria |

Default sensato 2026: **Redis 7.4+** ou **Valkey 8** (igual API).

## B. Patterns obrigatórios

### B.1 SEMPRE com TTL (anti-leak)

```ts
// ❌ ERRADO — chave eterna, OOM em N semanas
await redis.set(`user:${id}`, data);

// ✅ CERTO — TTL explícito
await redis.setEx(`user:${id}`, 3600, data);             // 1 hora
await redis.set(`user:${id}`, data, { EX: 3600 });       // ioredis
```

Exceção: keys que precisam durar (counters de billing) — documente em
`intelligence.yml` `redis-patterns.no_ttl_keys: ["billing:*"]`.

### B.2 Multi-tenant via prefix (anti cross-tenant leak)

```ts
// ❌ Risco de colisão
const key = `user:${userId}:profile`;

// ✅ Multi-tenant safe
const key = `tenant:${tenantId}:user:${userId}:profile`;

// Helper centralizado
function tk(tenantId: string, ...parts: string[]): string {
  return `tenant:${tenantId}:${parts.join(':')}`;
}
await redis.setEx(tk(tenantId, 'user', userId, 'profile'), 3600, data);
```

Pra invalidar todo cache do tenant em mudança de plano:
```ts
const stream = redis.scanIterator({ MATCH: `tenant:${tenantId}:*`, COUNT: 100 });
for await (const key of stream) await redis.del(key);
```

### B.3 Eviction policy correta

```bash
# redis.conf ou docker-compose env
maxmemory 2gb
maxmemory-policy allkeys-lru    # ou volatile-lru, allkeys-lfu
```

| Policy | Quando usar |
|---|---|
| `noeviction` | **NUNCA em prod cache** — bloqueia escritas em OOM |
| `allkeys-lru` | Default cache geral |
| `allkeys-lfu` | Cache com hot keys claros |
| `volatile-lru` | Mistura cache + session — só keys com TTL evictáveis |
| `volatile-ttl` | Prefere expirar primeiro o que tem TTL mais curto |

### B.4 Persistence (RDB + AOF)

| Use case | Config |
|---|---|
| Cache puro (perda OK) | RDB cada 15min, sem AOF |
| Session store | RDB + AOF `appendfsync everysec` |
| Source of truth (raro) | AOF `appendfsync always` + RDB |
| Rate limit / queue | RDB + AOF `everysec` (BullMQ exige) |

## C. Distributed lock — Redlock, NÃO SETNX cru

```ts
// ❌ Race condition em segundos: 2 processos pegam o lock
const got = await redis.setNX('lock:job', '1');
if (got) await doWork();

// ✅ Redlock formal (multi-node, com TTL automático e drift handling)
import Redlock from 'redlock';
const redlock = new Redlock([redisA, redisB, redisC], { retryCount: 0 });

let lock;
try {
  lock = await redlock.acquire(['lock:job'], 10_000);   // 10s TTL
  await doWork();
} finally {
  if (lock) await lock.release();
}
```

Pra single-instance dev, `redlock` com 1 node ainda funciona corretamente
(extends + release com Lua script).

## D. Pipeline / Transactions

```ts
// ❌ N round-trips
for (const id of userIds) {
  await redis.hgetall(`user:${id}`);
}

// ✅ Pipeline — 1 round-trip
const pipeline = redis.pipeline();
userIds.forEach(id => pipeline.hgetall(`user:${id}`));
const results = await pipeline.exec();
```

Para atomicidade real: `MULTI/EXEC` (transaction):
```ts
const result = await redis.multi()
  .incr('counter')
  .expire('counter', 60)
  .exec();
```

Para script Lua (atomicidade + lógica condicional):
```ts
const script = `
  local v = redis.call('GET', KEYS[1])
  if v == false then return 0 end
  return redis.call('INCR', KEYS[1])
`;
await redis.eval(script, 1, 'mykey');
```

## E. Cache-aside vs Write-through

### Cache-aside (default, mais simples)

```ts
async function getUser(id: string) {
  const cached = await redis.get(`user:${id}`);
  if (cached) return JSON.parse(cached);

  const fresh = await db.user.findUnique({ where: { id } });
  await redis.setEx(`user:${id}`, 300, JSON.stringify(fresh));
  return fresh;
}

async function updateUser(id: string, data) {
  const updated = await db.user.update({ where: { id }, data });
  await redis.del(`user:${id}`);   // INVALIDAR — não atualizar (race condition)
  return updated;
}
```

### Write-through (escritas consistentes)

```ts
await db.user.update(...);
await redis.setEx(`user:${id}`, 300, JSON.stringify(newData));
// Risco: se Redis cair entre as 2 chamadas, cache fica stale
```

**Regra**: cache-aside + invalidação > write-through em 95% dos casos.

## F. Pub/Sub vs Streams

| Use case | Tool |
|---|---|
| Fire-and-forget broadcast (cache invalidation) | **PUB/SUB** |
| Job queue com retry + dedup | **Streams** + consumer groups (ou BullMQ) |
| Event sourcing leve | **Streams** com `XAUTOCLAIM` |

```ts
// Stream com consumer group
await redis.xadd('events', '*', 'type', 'apt.created', 'data', JSON.stringify(d));

// Consumer
const messages = await redis.xreadgroup('GROUP', 'workers', 'worker-1',
  'COUNT', 10, 'BLOCK', 5000, 'STREAMS', 'events', '>');

// Cleanup de consumers mortos (cada 1min)
await redis.xautoclaim('events', 'workers', 'worker-1', 60_000, '0');
```

## G. Rate limit (sliding window > fixed window)

```ts
// Fixed window — easy mas tem burst no boundary
const key = `rl:${userId}:${Math.floor(Date.now()/60_000)}`;
const count = await redis.incr(key);
if (count === 1) await redis.expire(key, 120);
if (count > limit) return rateLimited;

// Sliding window via sorted set (mais preciso)
const now = Date.now();
const key = `rl:${userId}`;
await redis.zadd(key, now, now);
await redis.zremrangebyscore(key, 0, now - 60_000);
const count = await redis.zcard(key);
if (count > limit) return rateLimited;
await redis.expire(key, 120);
```

Lib pronta: `@upstash/ratelimit` (compatível).

## H. Connection pool + TLS + AUTH

```ts
// Pool sizing em ioredis
const redis = new Redis({
  host: process.env.REDIS_HOST,
  port: 6379,
  password: process.env.REDIS_PASSWORD,        // OBRIGATÓRIO em prod
  tls: { rejectUnauthorized: true },           // OBRIGATÓRIO em prod
  maxRetriesPerRequest: 3,
  retryStrategy: (times) => Math.min(times * 50, 2000),
  enableReadyCheck: true,
  connectTimeout: 10_000,
  // BullMQ exige:
  maxRetriesPerRequest: null,
});
```

## I. Cluster mode (> 25GB ou > 100k ops/s)

```ts
import { Cluster } from 'ioredis';
const cluster = new Cluster([
  { host: 'redis-1.internal', port: 6379 },
  { host: 'redis-2.internal', port: 6379 },
  { host: 'redis-3.internal', port: 6379 },
]);

// Hash tags pra co-locar keys relacionadas no mesmo slot:
await cluster.set('{tenant:abc}:user:1', data);  // {} = hash tag
await cluster.set('{tenant:abc}:user:2', data);  // mesmo slot — permite MULTI
```

## J. Observability

```ts
// Habilitar slow log (queries > 10ms)
await redis.configSet('slowlog-log-slower-than', 10000);  // microseconds
await redis.configSet('slowlog-max-len', 1000);

// Métricas pra alertar
const info = await redis.info('stats');
// keyspace_hits / (keyspace_hits + keyspace_misses) > 0.85 = OK
// evicted_keys crescente = aumentar maxmemory ou TTLs
// used_memory_rss vs used_memory = fragmentation > 1.5 = MEMORY DOCTOR
```

Alertas obrigatórios:
- Hit rate < 80%
- Evictions > 0 (sinal de OOM próximo)
- Connected clients > 80% do `maxclients`
- Memory > 80% do `maxmemory`
- Slow log com entries

## K. Vector search (Redis 8+ Vector Sets)

```ts
// Alternativa a Pinecone se já tem Redis
await redis.ft.create('idx:products', {
  '$.embedding': { type: 'VECTOR', algo: 'HNSW', dims: 1536, metric: 'COSINE' },
  '$.name':      { type: 'TEXT' }
});

const result = await redis.ft.search('idx:products',
  '@embedding:[VECTOR_RANGE 0.5 $vec]',
  { params: { vec: queryEmbedding } }
);
```

Economia: Pinecone ~$70/mo → Redis com vector sets ~$15/mo no mesmo cluster.

## L. Greps obrigatórios

```bash
# Chave sem TTL (memory leak)
rg -n "redis\.set\(" --type ts | grep -v "(EX:|setEx|SETEX|expire)"

# SETNX cru (race condition)
rg -n "setnx\(|setNX\(" --type ts | grep -v "redlock"

# Key sem tenant prefix em multi-tenant
rg -n "redis\.(get|set)\(" --type ts | grep -v "tenant:"

# noeviction em config
grep -E "maxmemory-policy[^=]*noeviction" docker-compose.yml redis.conf 2>/dev/null

# Connection sem TLS em prod
rg -n "new Redis\(" --type ts | grep -v "tls"
```

## M. Output em sec.html

```
┌─ Redis Patterns (Módulo 9) ──────────────────────────────┐
│ Engine                        : Redis 7.4 ✅              │
│ Chaves sem TTL                : 0 ✅ (era 23)             │
│ Multi-tenant prefix (tk())    : ✅ helper centralizado   │
│ Eviction policy               : allkeys-lru ✅            │
│ AOF habilitado (session)      : ✅ everysec               │
│ Redlock pra distributed lock  : ✅ (não SETNX cru)        │
│ Pipeline em batch ops         : ✅                        │
│ TLS + AUTH em prod            : ✅                        │
│ Slow log ativo                : ✅ > 10ms                 │
│ Cache hit rate (24h)          : 87% ✅ (meta > 80%)       │
│ Evictions (24h)               : 0 ✅                      │
│ Cluster mode                  : N/A (< 25GB)              │
│ Status                        : ✅ PROD-READY             │
└───────────────────────────────────────────────────────────┘
```

## N. Intelligence

```yaml
# .blindar/intelligence.yml
redis-patterns:
  no_ttl_keys:          # chaves intencionalmente sem TTL
    - "billing:*"
    - "config:global:*"
  exempt_tenant_prefix: # caches globais sem tenant
    - "exchange_rates:*"
    - "feature_flags:*"
  cluster_required_gb: 25
  inline_override_marker: "// @blindar:redis-keep"
```

## O. Anti-padrões

- ❌ Chave sem TTL (memory leak garantido)
- ❌ `SETNX` cru pra distributed lock (race)
- ❌ Cache key sem prefix tenant em multi-tenant
- ❌ `maxmemory-policy noeviction` em cache prod
- ❌ Redis sem AUTH em prod
- ❌ Single Redis sem replica (SPOF)
- ❌ Pipeline esquecido (N round-trips desnecessários)
- ❌ Write-through em vez de cache-aside + invalidate
- ❌ `KEYS *` em prod (bloqueia Redis — use SCAN)
- ❌ FLUSHALL em script (apaga tudo de todos os tenants)
- ❌ Sem slow log (queries lentas invisíveis)
- ❌ Hit rate < 50% sem investigar (TTL muito curto?)
