---
name: process-resilience
category: resilience
module: 13
priority: P0
description: |
  Garante que processo/sistema/banco NÃO TRAVA nunca. Cobre 7 vetores:
  health checks (live/ready/deep), graceful shutdown (drain + finish),
  backpressure (queue cheia → 503 amigável), ulimits/OOM/file descriptors,
  watchdog/heartbeat externo, long-running transaction killer, deadlock
  retry automático. Complementa resilience.md (breakers/pools) com foco em
  "processo morre limpo, nunca trava silencioso".
---

# Agent: process-resilience

## Missão

`resilience.md` cobre falhas externas (breakers, pools, retry). Este
agente cobre **a saúde do PRÓPRIO processo**: como ele responde quando o
sistema operacional pergunta "está vivo?", como morre sem perder
requests em vôo, como aceita gracioso parar de aceitar trabalho quando
sobrecarregado em vez de travar tudo.

## Quando rodar

- Módulo 13 selecionado
- Tipo do projeto ∈ {saas, ecom, api, mobile} com backend long-running
- Operador pediu "alta disponibilidade", "uptime", "não cair", "k8s"

## A. Health checks em 3 níveis

```ts
// /health/live — "o processo está respondendo?"
// Sem dependência externa. K8s usa pra liveness probe → mata pod se falhar.
app.get('/health/live', (req, res) => res.json({ status: 'ok', pid: process.pid }));

// /health/ready — "posso receber tráfego?"
// Checa dependências críticas. K8s usa pra readiness → tira do LB se falhar.
app.get('/health/ready', async (req, res) => {
  const checks = await Promise.allSettled([
    db.$queryRaw`SELECT 1`,                          // DB
    redis.ping(),                                    // cache
    s3.headBucket({ Bucket: BUCKET }).promise()      // storage
  ]);
  const failed = checks.filter(c => c.status === 'rejected');
  if (failed.length > 0) return res.status(503).json({ status: 'degraded', failed });
  res.json({ status: 'ok' });
});

// /health/deep — "tudo OK de verdade?"
// Inclui métricas de saúde: pool DB, queue size, memory, event loop lag.
// Usado por watchdog externo, NÃO por k8s (caro).
app.get('/health/deep', async (req, res) => {
  res.json({
    status: 'ok',
    db_pool: { active: pool.totalCount, idle: pool.idleCount, waiting: pool.waitingCount },
    queue: { pending: await queue.count('pending'), failed: await queue.count('failed') },
    memory: process.memoryUsage(),
    event_loop_lag_ms: await measureEventLoopLag(),
    uptime_sec: process.uptime()
  });
});
```

### Regras

- **liveness**: rapidíssima (< 50ms), sem dependência externa → senão k8s mata pod por timeout
- **readiness**: pode ser lenta (~500ms), checa real dependência
- **deep**: protegido por auth (vaza info), só pra dashboard interno
- Endpoint dedicado, NÃO `/api/health` que pode bater rate limit

## B. Graceful shutdown (não perder request em vôo)

```ts
let isShuttingDown = false;

async function shutdown(signal: string) {
  console.log(`[shutdown] received ${signal}, starting graceful shutdown`);
  isShuttingDown = true;

  // 1. Para de aceitar novas conexões (HTTP server.close não fecha sockets ativos)
  server.close(() => console.log('[shutdown] HTTP server stopped accepting'));

  // 2. Espera requests em vôo terminarem (timeout 30s)
  await waitForInflight({ timeoutMs: 30_000 });

  // 3. Termina jobs em vôo
  await queue.shutdown({ timeoutMs: 30_000 });   // BullMQ tem .close({ force: false })

  // 4. Fecha conexões DB (drain pool)
  await prisma.$disconnect();
  await redis.quit();

  // 5. Sai limpo
  console.log('[shutdown] done, exiting');
  process.exit(0);
}

// SIGTERM = k8s/systemd pedindo educadamente
process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));

// Durante shutdown, readiness começa a falhar (k8s para de mandar tráfego)
app.get('/health/ready', (req, res) => {
  if (isShuttingDown) return res.status(503).json({ status: 'shutting_down' });
  // ... resto
});
```

### Regras

- **Drain primeiro, depois encerra** — fluxo: stop accepting → readiness 503 → finish inflight → close pools → exit 0
- **Timeout obrigatório** (k8s SIGKILL em 30-40s se não saiu) — `terminationGracePeriodSeconds: 30`
- **K8s preStop hook** pode adicionar delay de 5s antes do SIGTERM (LB precisa propagar remoção)
- Worker (job consumer) tem que parar de pegar novos jobs e terminar os atuais

## C. Backpressure (não travar aceitando infinito)

### Sintoma: queue/buffer cresce sem limite → OOM → processo morre sem aviso

```ts
// HTTP middleware: rejeita 503 se overloaded
const MAX_INFLIGHT = 1000;
let inflight = 0;

app.use((req, res, next) => {
  if (inflight >= MAX_INFLIGHT) {
    res.set('Retry-After', '5');
    return res.status(503).json({ code: 'OVERLOADED' });
  }
  inflight++;
  res.on('finish', () => inflight--);
  res.on('close', () => inflight--);
  next();
});
```

### Event loop lag detector

```ts
import { monitorEventLoopDelay } from 'perf_hooks';
const h = monitorEventLoopDelay({ resolution: 20 });
h.enable();

setInterval(() => {
  const lag = h.mean / 1e6;  // ms
  if (lag > 200) {
    // event loop travado → começar a rejeitar
    isOverloaded = true;
  } else if (lag < 50) {
    isOverloaded = false;
  }
  h.reset();
}, 5000);
```

### Queue com limite + DLQ

- BullMQ: `concurrency: 10`, `removeOnComplete: 1000`, `removeOnFail: 5000`
- Quando queue > N pending → backoff produtor (não enfileira mais), avisa cliente

## D. ulimits / OOM / file descriptors

### Container deve declarar limits

```yaml
# k8s deployment
resources:
  requests:
    cpu: 250m
    memory: 256Mi
  limits:
    cpu: 1000m
    memory: 512Mi    # OOMKill se passar — melhor que ficar swapping
```

### Process-level limits

```bash
# Dockerfile / entrypoint
ulimit -n 65536      # file descriptors (sockets + arquivos abertos)
ulimit -u 4096       # processes
ulimit -v unlimited  # virtual memory
```

### Node.js heap

```bash
# Limite explícito, não deixar V8 escolher
node --max-old-space-size=384 server.js   # 384 MB heap (deixa 128 pra outro)
```

### Detect leak antes de OOM

```ts
setInterval(() => {
  const mem = process.memoryUsage();
  if (mem.heapUsed > 400 * 1024 * 1024) {     // > 400 MB
    logger.warn('high_heap', mem);
    // se sustained > 5min → restart preventivo (que k8s faz)
  }
}, 60_000);
```

### NUNCA crescer estrutura unbounded

```ts
// RUIM
const cache = new Map();   // cresce eterno → OOM
function get(id) { return cache.get(id) ?? fetchAndCache(id); }

// BOM — LRU com cap
import { LRUCache } from 'lru-cache';
const cache = new LRUCache({ max: 5000, ttl: 5 * 60_000 });
```

## E. Watchdog externo (heartbeat)

### Quem vigia o vigia?

App pode estar "vivo" pro k8s (responde liveness) mas com event loop travado em loop infinito. Watchdog externo cobre.

```ts
// Heartbeat ativo: app empurra status pra serviço externo a cada 30s
setInterval(async () => {
  await fetch('https://watchdog.internal/beat', {
    method: 'POST',
    body: JSON.stringify({
      service: 'salon-api',
      instance: hostname,
      ts: Date.now(),
      eventLoopLag: lastLag,
      memoryMB: process.memoryUsage().heapUsed / 1024 / 1024
    })
  });
}, 30_000);

// Watchdog: se não recebe beat de instância em 90s, dispara alerta
// (PagerDuty, Slack, oncall)
```

### Alternativas prontas

- **Better Uptime / Healthchecks.io / Cronitor** — você manda heartbeat HTTP, eles alertam se sumir
- **Pingdom** — chamadas externas periódicas pro /health/ready

## F. Long-running transaction killer

### Problema

Transação aberta 30min trava locks → outras queries esperam → cascata.

### Postgres

```sql
-- Servidor (postgresql.conf)
idle_in_transaction_session_timeout = '60s';  -- mata tx idle > 60s

-- Cron mata tx muito longas
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE state IN ('active', 'idle in transaction')
  AND xact_start < now() - interval '5 minutes'
  AND datname = current_database()
  AND query NOT LIKE '%pg_dump%'     -- exceções
  AND query NOT LIKE '%vacuum%';
```

### MySQL

```sql
SET GLOBAL innodb_lock_wait_timeout = 50;
SET GLOBAL wait_timeout = 60;

-- Kill via:
SELECT CONCAT('KILL ', id, ';') FROM information_schema.processlist
WHERE time > 300 AND command != 'Sleep';
```

### App-level

```ts
// Wrapper que mata transaction se passa de N segundos
async function withTx<T>(fn: (tx) => Promise<T>, timeoutMs = 5000): Promise<T> {
  return Promise.race([
    prisma.$transaction(fn),
    new Promise<T>((_, rej) => setTimeout(() => rej(new Error('tx_timeout')), timeoutMs))
  ]);
}
```

## G. Deadlock retry automático

### Postgres `serialization_failure` (40001) e `deadlock_detected` (40P01)

Não é bug do app — é Postgres pedindo pra você tentar de novo.

```ts
async function withDeadlockRetry<T>(fn: () => Promise<T>, maxAttempts = 3): Promise<T> {
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      return await fn();
    } catch (err: any) {
      const code = err.code || err.meta?.code;
      const isRetryable = code === '40001' || code === '40P01';
      if (!isRetryable || attempt === maxAttempts) throw err;

      // Backoff com jitter
      const delay = 50 * 2 ** attempt + Math.random() * 100;
      await new Promise(r => setTimeout(r, delay));
      logger.warn('deadlock_retry', { attempt, code });
    }
  }
  throw new Error('unreachable');
}

// Uso
await withDeadlockRetry(() => prisma.$transaction(async tx => {
  // sua tx aqui
}));
```

## H. Crash loop protection

Se app crasha N vezes em janela curta, k8s entra em `CrashLoopBackOff` (espera exponencial). Detectar e alertar:

```yaml
# Liveness com falha alta = não fica reiniciando infinito
livenessProbe:
  httpGet: { path: /health/live, port: 3000 }
  initialDelaySeconds: 30      # tempo pro app subir
  periodSeconds: 10
  timeoutSeconds: 3
  failureThreshold: 3          # 3 falhas → restart
```

Logs estruturados + alertar quando `kubectl get pod` mostra `restartCount > 3` em 1h.

## I. Output esperado em sec.html

```
┌─ Process Resilience (Módulo 13) ─────────────────────────┐
│ Health /live /ready /deep    : ✅ 3 endpoints              │
│ K8s probes configurados      : ✅ liveness + readiness    │
│ Graceful shutdown            : ✅ SIGTERM drain 30s        │
│ Backpressure (503 overload)  : ✅ + event loop lag detect │
│ ulimits declarados           : ✅ fd=65536                 │
│ Heap limit (--max-old-space) : ✅ 384 MB                   │
│ Container memory limit       : ✅ 512 Mi                   │
│ LRU cache (não unbounded)    : ✅ 5 caches auditados       │
│ Watchdog externo             : ✅ heartbeat 30s            │
│ Postgres idle_in_tx_timeout  : ✅ 60s                      │
│ Cron mata tx > 5min          : ✅                          │
│ Deadlock retry automático    : ✅ 40001 + 40P01            │
│ App-level tx timeout         : ✅ 5s default               │
│ Status                       : ✅ NEVER-FREEZES           │
└───────────────────────────────────────────────────────────┘
```

## Anti-padrões (CRIT pra alta disponibilidade)

- ❌ Sem health endpoints (k8s não sabe quando reiniciar)
- ❌ Mesma rota pra liveness e readiness (não dá pra distinguir "processo morto" de "dependência caiu")
- ❌ Liveness checa DB (DB caiu = pod morto = cascata)
- ❌ Sem SIGTERM handler (k8s SIGKILL = perde requests em vôo)
- ❌ Sem timeout em graceful shutdown (espera infinito)
- ❌ Cache `new Map()` sem cap (OOM)
- ❌ Sem `--max-old-space-size` em Node (V8 escolhe errado)
- ❌ Container sem memory limit (vai swapping = travado vivo)
- ❌ Transação aberta > 5min sem alerta
- ❌ `serialization_failure` sem retry (erro 500 desnecessário pro user)
- ❌ Sem watchdog externo (event loop travado passa despercebido)
- ❌ Queue/buffer sem limite máximo (cresce até OOM)
