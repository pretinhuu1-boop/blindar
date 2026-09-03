---
name: llm-latency-observability
category: ai
module: 6
priority: P1
lead: ai-lead
authority: implement
description: |
  A chamada mais lenta e mais variável do sistema é a única sem relógio. Cobra instrumentação de duração (timer, histograma ou span) em toda chamada a provedor de LLM — sem ela o p95 do produto é invisível.
---

# Agent: llm-latency-observability

Uma chamada a provedor de LLM leva de 800ms a 40 segundos. Varia com o tamanho do
prompt, com a fila do provedor, com a hora do dia e com o modelo escolhido — e é
o gargalo de quase toda aplicação que a usa.

Sem medir duração por chamada, o p95 do produto é invisível. O time discute "o
bot está lento" com base em impressão; a regressão que dobrou a latência entra num
deploy qualquer sem deixar rastro; e a decisão de trocar de modelo é tomada por
intuição, com um custo que ninguém consegue comparar contra o ganho.

Instrumentar é barato: marcar o tempo antes e depois, e emitir a duração com o
modelo e o resultado. O que não dá é descobrir depois — **telemetria não tem
retroativo**.

## O que o check já garante

[`check-llm-latency-observability.sh`](../templates/checks/check-llm-latency-observability.sh):

| Situação | Severidade |
|---|---|
| Nenhuma chamada de LLM instrumentada | **med** |
| Parte instrumentada, parte não (cobertura desigual) | **low** por arquivo |

Localiza a chamada de fato (`messages.create`, `chat.completions.create`,
`generateContent`, `.invoke(`, `acompletion(`), não o import. Aceita como
instrumentação: `Date.now()`, `performance.now()`, `process.hrtime`,
`perf_counter`, histograma de métrica, span de tracing, decorator de timing.

Auto-skip em projeto que não usa LLM, e em projeto cujas chamadas só aparecem em
teste ou exemplo.

## O que registrar em cada chamada

Duração sozinha responde pouco. O conjunto mínimo que permite investigar:

| Campo | Por quê |
|---|---|
| `duration_ms` | o número em disputa |
| `modelo` | comparar troca de modelo exige separar por modelo |
| `resultado` (ok / erro / timeout) | latência de erro e de sucesso têm distribuições diferentes |
| `tokens_entrada` / `tokens_saida` | o principal preditor de duração — e o de custo |
| `tentativa` | retry inflado some no agregado e explica cauda longa |

Com isso, `p50 / p95 / p99` por modelo viram uma consulta, e "está lento" vira
uma pergunta respondível.

## O que só se prova em produção

| Verificar | Por quê |
|---|---|
| p95 sob carga real | o provedor enfileira; a latência de um teste isolado não representa |
| Timeout definido e menor que o do cliente | sem timeout, a requisição do usuário fica presa até o socket morrer |
| Retry com backoff não multiplica a espera | três tentativas de 20s são 60s para quem espera |
| Custo por conversa | latência e custo sobem juntos; medir um sem o outro decide errado |
