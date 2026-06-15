---
name: event-driven
category: architecture
module: 13
priority: P2
description: |
  Arquitetura event-driven: Kafka/RabbitMQ/NATS/SQS, outbox pattern pra
  publish reliability, CQRS quando justifica, Event Sourcing com cuidado,
  saga pattern pra transação distribuída, eventual consistency com
  observability. Resolve "microservices acoplados via REST síncrono".
---

# Agent: event-driven

## Missão

Microservices com REST síncrono = dependência transitiva (A→B→C, qualquer
um cai derruba tudo). Eventos desacoplam e escalam — mas trazem
complexidade. Este agente prescreve quando vale + como fazer certo.

## Quando rodar

- Módulo 13 selecionado
- Detectado: `kafkajs`, `amqplib`, `nats`, `@aws-sdk/client-sqs`, `bullmq`
- Operador pediu "microservices", "events", "CQRS", "eventual consistency"

## A. Quando usar event-driven (não é pra tudo)

| Vale | NÃO vale |
|---|---|
| Múltiplos consumers do mesmo evento | Comunicação 1:1 simples |
| Desacoplamento entre bounded contexts | Monolito que funciona |
| Audit trail natural | Equipe < 5 devs |
| Replay pra debug ou backfill | Time não conhece async patterns |
| Escala assimétrica (1 produz, 10 consomem) | Latência síncrona crítica (chat) |

## B. Escolha de broker

| Broker | Quando |
|---|---|
| **Kafka** | Throughput alto (>10k msg/s), replay, stream processing |
| **RabbitMQ** | Routing complexo, padrão AMQP, baixa latência |
| **NATS** | Cloud-native, lightweight, JetStream pra durability |
| **AWS SQS + SNS** | Tudo AWS, managed, simples |
| **Redis Streams** | Já usa Redis, throughput médio |

## C. Outbox pattern (publish reliability)

Problema: você commitou no banco mas publish no Kafka falhou. Estado
divergente.

```sql
CREATE TABLE outbox (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid_v7(),
  aggregate_id UUID NOT NULL,
  event_type  TEXT NOT NULL,
  payload     JSONB NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  published_at TIMESTAMPTZ
);

CREATE INDEX idx_outbox_unpublished ON outbox(created_at) WHERE published_at IS NULL;
```

```ts
// Tx do banco grava entidade + evento na outbox ATOMICAMENTE
await db.$transaction([
  db.appointment.create({ data }),
  db.outbox.create({ data: { aggregate_id: data.id, event_type: 'apt.created', payload: data } })
]);

// Worker separado publica
@Cron('*/5 * * * * *')   // 5s
async publishOutbox() {
  const events = await db.outbox.findMany({
    where: { published_at: null }, take: 100, orderBy: { created_at: 'asc' }
  });
  for (const e of events) {
    await kafka.send({ topic: e.event_type, messages: [{ key: e.aggregate_id, value: JSON.stringify(e.payload) }] });
    await db.outbox.update({ where: { id: e.id }, data: { published_at: new Date() } });
  }
}
```

CDC (Change Data Capture) com Debezium é alternativa zero-código.

## D. Consumer idempotente

Mesmo evento pode chegar 2x (at-least-once). Consumer deve:

```ts
@KafkaConsumer('apt.created')
async handleAptCreated(event) {
  // Dedup por event_id
  const seen = await db.processedEvents.findUnique({ where: { event_id: event.id } });
  if (seen) return { skipped: true };
  await db.$transaction([
    doWork(event),
    db.processedEvents.create({ data: { event_id: event.id } })
  ]);
}
```

## E. Schema registry (Avro/Protobuf/JSON Schema)

Sem schema validation:
- Producer muda campo, breaks consumers silenciosamente

Com Confluent Schema Registry ou similar:
- Producers validam ao publicar
- Consumers validam ao consumir
- Breaking change → versionamento (v1, v2 coexistem N meses)

## F. CQRS — quando vale

Separar write model (commands) de read model (queries):

```
Command: POST /appointments
   ↓
write_model (Postgres) ← source of truth
   ↓ event
read_model_search (Meilisearch) ← projeção
read_model_dashboard (Materialized View)
```

**Vale** quando: leituras 100x mais que escritas, agregados pesados, search.
**NÃO vale** quando: CRUD simples.

## G. Event Sourcing — cuidado

Source of truth = log de eventos. Estado atual = replay.

**Vale** quando: audit regulatório obrigatório, time travel debugging,
domínio rico (financeiro, jurídico).
**NÃO vale** quando: queries ad-hoc frequentes (pesado), time pequeno.

Event store: EventStoreDB, Kurrent, ou Postgres com tabela append-only.

## H. Saga pattern (transação distribuída)

Pra processo que envolve N services. Choreography (cada um reage) ou
Orchestration (orchestrator coordena).

```
1. Order created (Order service)
2. Reserve stock (Inventory service)         ← se falhar, cancel order
3. Charge card (Payment service)              ← se falhar, release stock
4. Send confirmation (Notification service)
```

Compensação em cada step pra rollback (semântico, não atômico).

## I. Ordering guarantee

- Kafka: garante ordering por **partition key**. Mesma chave = mesma partição = ordem.
- SQS FIFO: ordering por message group ID.
- Pra ordering global: 1 partição (perde paralelismo).

NUNCA depender de ordering global em sistema distribuído. Designs com
`occurred_at` no payload + consumer que respeita.

## J. Observability

- Trace context propagado entre services (W3C Trace Context)
- Dashboard de consumer lag (alerta se > 1min)
- Replay tool pra debug
- DLQ tracking

## K. Greps

```bash
# Publish sem outbox (perde mensagem se DB rollback)
rg -n "kafka\.send\(|sqs\.sendMessage" --type ts -B 5 | rg -v "outbox|cdc"

# Consumer sem dedup
rg -n "@KafkaConsumer|@SqsConsumer" --type ts -A 10 | rg -v "(processed|seen|idempot)"

# Sem schema validation
rg -n "JSON\.parse\(.*messages\[0\]" --type ts
```

## Output em sec.html

```
┌─ Event-Driven (Módulo 13) ───────────────────────────────┐
│ Broker                        : Kafka 3.7               │
│ Outbox pattern                : ✅ + worker publish     │
│ Consumers idempotentes        : ✅ processed_events     │
│ Schema registry               : ✅ Confluent            │
│ Schema versioning             : ✅ v1+v2 coexistem      │
│ CQRS aplicado em              : 2 contexts              │
│ Saga (orchestration)          : payment-flow            │
│ Consumer lag (p95)            : 1.2s ✅ (alerta > 60s)  │
│ DLQ items                     : 12 (revisão semanal)    │
│ Replay tool                   : ✅                       │
│ Status                        : ✅ DECOUPLED            │
└───────────────────────────────────────────────────────────┘
```

## Anti-padrões

- ❌ Publish direto sem outbox (perde msg se DB rollback)
- ❌ Consumer sem idempotência (rodando 2x dobra trabalho)
- ❌ Schema livre (producer muda, consumers quebram silenciosamente)
- ❌ Depender de ordering global
- ❌ CQRS em CRUD simples (over-engineering)
- ❌ Event Sourcing em time pequeno sem necessidade
- ❌ Saga sem compensação (transação fica metade feita)
- ❌ Sem DLQ (consumer fail vira queue infinita)
- ❌ Sem trace context (não consegue debug cross-service)
- ❌ Manual publish em código de feature (deve ser dentro da transaction)
