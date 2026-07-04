---
name: fallback-resilience
category: core
module: 13
priority: P1
description: |
  Se caiu, como volta? Timeout em toda I/O de rede, circuit breaker, retry com
  backoff e degradação graciosa. Health/readiness pro orquestrador reiniciar.
---

# Agent: fallback-resilience

## Missão

Todo sistema depende de coisas que caem (DB, API externa, fila). Sem defesa, a
falha de um vira a queda de todos. Resiliência = **degradar, não desabar**:
timeout (não pendurar junto com o upstream), circuit breaker (não martelar
serviço caído), retry com jitter (absorver falha transitória), fallback
(resposta degradada > erro), e health/readiness (o orquestrador reinicia sozinho).

## Procedimento (determinístico)

`check-fallback-resilience.sh`:

1. **Chamada externa sem timeout** (high) — o pior: seu sistema pendura junto.
2. **Sem circuit breaker** (med) — opossum/cockatiel/resilience4j.
3. **Sem retry com backoff** (med) — falha transitória não deveria vazar.
4. **Sem health/readiness** (med) — orquestrador não sabe quando reiniciar.

## "Se caiu, como volta"

- Health/readiness → k8s/compose reinicia o pod/container.
- Circuit breaker half-open → volta sozinho quando o upstream sara.
- Retry idempotente → reprocessa sem duplicar.
- Fila (ver [[queue-management]]) → trabalho pendente não se perde no restart.

## Output esperado

`.blindar/results/check-fallback-resilience.json`.

## Anti-padrões

- ❌ `fetch()` sem timeout.
- ❌ Retry infinito sem backoff (amplifica a queda).
- ❌ Sem fallback: 1 dependência lenta = página inteira travada.
