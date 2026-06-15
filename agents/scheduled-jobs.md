---
name: scheduled-jobs
category: ops
module: 13
priority: P0
description: |
  Cron robusto em produção: distributed lock (Redlock) pra exactly-once
  em multi-instance, observability de jobs atrasados, retry com jitter,
  DLQ, watchdog, idempotência obrigatória, timezone consistente UTC,
  alertas de jobs que param de rodar (silent failure). Resolve toda
  classe de bug "job rodou 3x em 3 servers" ou "job parou semana
  passada e ninguém viu".
---

# Agent: scheduled-jobs

## Missão

Cron em multi-instance vira pesadelo: 3 servers, mesmo job, 3 execuções.
Ou: job parou semana passada, ninguém percebeu até cliente reclamar de
faturamento perdido. Este agente prescreve cron production-grade.

## Quando rodar

- Módulo 13 selecionado
- Detectado: `node-cron`, `@nestjs/schedule`, BullMQ repeatable jobs,
  `agenda`, cron files em K8s, EventBridge rules
- Operador pediu "cron", "agendado", "recorrente"

## A. Exactly-once em multi-instance (Redlock)

```ts
import { Redlock } from 'redlock';
const redlock = new Redlock([redisA, redisB, redisC], {
  retryCount: 0,                          // não esperar lock se outro pegou
  driftFactor: 0.01,
});

@Cron('0 3 * * *')                         // 3am todo dia
async dailyReconciliation() {
  let lock;
  try {
    lock = await redlock.acquire(['cron:daily-reconciliation'], 10 * 60 * 1000);  // 10min
  } catch { return; }                      // outro server pegou; sai sem erro

  try {
    await doWork();
  } finally {
    await lock.release();
  }
}
```

NUNCA confiar em `single-instance` em produção. Sempre lock.

## B. Idempotência (job pode rodar 2x e tudo OK)

```ts
async processPayment(invoiceId: string) {
  // Verifica se já processou ANTES de fazer
  const inv = await db.invoice.findUnique({ where: { id: invoiceId } });
  if (inv.processedAt) return { skipped: 'already_processed' };

  await db.$transaction(async tx => {
    await tx.invoice.update({
      where: { id: invoiceId, processedAt: null },  // optimistic lock
      data: { processedAt: new Date() }
    });
    await tx.payment.create(...);
  });
}
```

## C. Timezone — sempre UTC

```ts
@Cron('0 3 * * *', { timeZone: 'UTC' })   // explícito
```

Conversão pra fuso do cliente acontece no momento de mostrar/enviar, NÃO
no cron schedule. Cron em "America/Sao_Paulo" quebra com DST.

## D. Observability — alertar quando para de rodar

```sql
CREATE TABLE cron_runs (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid_v7(),
  job_name    TEXT NOT NULL,
  started_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  ended_at    TIMESTAMPTZ,
  status      TEXT NOT NULL CHECK (status IN ('running','success','failed','timeout')),
  duration_ms INTEGER,
  error       TEXT,
  result      JSONB
);
CREATE INDEX idx_cron_recent ON cron_runs(job_name, started_at DESC);
```

```ts
// Wrap de TODO job
async function trackCron(name: string, fn: () => Promise<any>, expectedFreqMs: number) {
  const run = await db.cronRun.create({ data: { job_name: name, status: 'running' } });
  const start = Date.now();
  try {
    const result = await fn();
    await db.cronRun.update({ where: { id: run.id }, data: {
      status: 'success', ended_at: new Date(), duration_ms: Date.now() - start, result
    }});
  } catch (err) {
    await db.cronRun.update({ where: { id: run.id }, data: {
      status: 'failed', ended_at: new Date(), error: err.message
    }});
    throw err;
  }
}
```

### Alerta "job sumido"

```ts
// Outro cron, watchdog
@Cron('*/5 * * * *')
async checkJobsAlive() {
  const expected = [
    { name: 'daily-reconciliation', maxAgeMs: 26 * 3600_000 },  // toleira 2h delay
    { name: 'hourly-cleanup',       maxAgeMs: 75 * 60_000 },
  ];
  for (const job of expected) {
    const last = await db.cronRun.findFirst({
      where: { job_name: job.name, status: 'success' },
      orderBy: { started_at: 'desc' }
    });
    if (!last || Date.now() - +last.started_at > job.maxAgeMs) {
      await alert.critical('cron_silent_failure', { job: job.name, last_success: last?.started_at });
    }
  }
}
```

## E. Retry com backoff + DLQ

```ts
// BullMQ repeatable + retry
queue.add('process-invoice', { id }, {
  attempts: 5,
  backoff: { type: 'exponential', delay: 5_000 },  // 5s, 10s, 20s, 40s, 80s
  removeOnComplete: 1000, removeOnFail: false,      // DLQ
});

// Limpa DLQ periodicamente, alertando antes de descartar
@Cron('0 4 * * 0')   // domingo 4am
async cleanDLQ() {
  const failed = await queue.getFailed(0, 1000);
  if (failed.length > 0) {
    await alert.warning('dlq_cleanup', { count: failed.length, sample: failed.slice(0, 5) });
    // não deleta sem revisão humana
  }
}
```

## F. Job longo — checkpoint + resume

```ts
async function reindexAll() {
  let lastId = await getCheckpoint('reindex');
  while (true) {
    const batch = await db.appointment.findMany({
      where: { id: { gt: lastId } }, take: 1000, orderBy: { id: 'asc' }
    });
    if (!batch.length) break;
    await indexBatch(batch);
    lastId = batch[batch.length - 1].id;
    await saveCheckpoint('reindex', lastId);    // resume aqui se crash
  }
}
```

## G. Concurrency cap (não saturar DB)

```ts
new Worker('process-invoice', handler, {
  concurrency: 5,                              // máx 5 jobs em paralelo
  limiter: { max: 100, duration: 60_000 },     // 100/min
});
```

## H. Greps

```bash
# Cron sem lock (CRIT em multi-instance)
rg -n "@Cron\(" --type ts -A 5 | rg -v "redlock|acquire|lock"

# Cron em timezone não-UTC
rg -n "@Cron\(" --type ts -A 2 | rg "timeZone.*America|timeZone.*Europe"

# Sem retry config
rg -n "queue\.add\(" --type ts -A 5 | rg -v "attempts:"

# Job sem tracking
rg -n "@Cron\(" --type ts -A 2 | rg -v "trackCron|cron_runs|cronRun"
```

## Output em sec.html

```
┌─ Scheduled Jobs (Módulo 13) ─────────────────────────────┐
│ Locks distribuídos (Redlock)  : ✅ 8/8 jobs              │
│ Timezone UTC em todos          : ✅                       │
│ Idempotência (optimistic lock) : ✅                       │
│ Tracking em cron_runs          : ✅                       │
│ Watchdog "job sumido"          : ✅ alerta < 2h           │
│ Retry exponencial + jitter     : ✅                       │
│ DLQ com revisão humana         : ✅ alerta antes de purge │
│ Checkpoint/resume em jobs longos: ✅                      │
│ Concurrency cap                : 5 default                │
│ Rate limiter                   : 100/min                  │
│ Jobs ativos                    : 8 (todos green últ 24h)  │
│ Status                         : ✅ EXACTLY-ONCE         │
└───────────────────────────────────────────────────────────┘
```

## Anti-padrões

- ❌ Cron sem lock em multi-instance (executa 1x por server)
- ❌ Timezone "America/Sao_Paulo" no cron (DST quebra anual)
- ❌ Sem tracking (job morre, ninguém vê)
- ❌ Sem watchdog (descobre semanas depois)
- ❌ Retry infinito sem DLQ (job ruim loopa eterno)
- ❌ DLQ deletada sem revisão (perde info de bug)
- ❌ Job não-idempotente (rodou 2x = duplica trabalho)
- ❌ Job longo sem checkpoint (crash = recomeça do zero)
- ❌ Sem concurrency cap (1 job custoso satura DB)
- ❌ Cron file em K8s sem sidecar de log estruturado
- ❌ Schedule em UI sem timezone explícito (operador edita errado)
