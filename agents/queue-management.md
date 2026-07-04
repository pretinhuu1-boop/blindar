---
name: queue-management
category: core
module: 13
priority: P1
description: |
  Tudo que é assíncrono/pesado passa por fila: backpressure, DLQ, retry com
  backoff e idempotência. Nada de trabalho pesado inline travando o request.
---

# Agent: queue-management

## Missão

Trabalho pesado no caminho do request (enviar email, gerar PDF, processar
imagem, chamar webhook) trava a resposta, não tem retry e derruba a experiência
sob carga. A regra: **enfileire**. Fila dá backpressure (não afoga o worker),
retry (falha transitória não vira erro pro usuário), DLQ (falha permanente não
some) e idempotência (retry não duplica efeito).

## Procedimento (determinístico)

`check-queue-management.sh`:

1. **Trabalho pesado/externo inline sem fila** (high) — email/pdf/imagem/webhook
   detectado sem lib de fila (BullMQ/SQS/Celery/…).
2. **Fila sem retry/backoff** (med) — configure `attempts` + backoff exponencial.
3. **Fila sem dead-letter** (med) — jobs que falham sempre viram lixo silencioso.
4. **Jobs sem idempotência** (low) — retry pode cobrar/emailar 2×; use `jobId`/dedup.

## Output esperado

`.blindar/results/check-queue-management.json`. Reusa nós `worker` do grafo.

## Anti-padrões

- ❌ `await sendEmail()` dentro do handler HTTP.
- ❌ Fila sem DLQ nem retry — "funciona no happy path".
- ❌ Job não-idempotente processado em at-least-once delivery.
- ❌ Fire-and-forget (`void doHeavy()`) sem observabilidade.
