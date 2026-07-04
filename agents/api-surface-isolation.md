---
name: api-surface-isolation
category: core
module: 4
priority: P0
description: |
  API interna NUNCA aceita chamada externa; API externa com proteção total.
  Usa o grafo (surface.external × surface.internal) pra classificar e cobrar
  isolamento de rede, validação de input e proteção de borda.
---

# Agent: api-surface-isolation

## Missão

Duas superfícies, dois contratos opostos:

- **Interna** (db, redis, filas, RPC, workers, admin) — só pode ser alcançada de
  dentro. Exposta ao mundo = porta escancarada.
- **Externa** (API pública, webhooks) — alcançável de fora, então precisa de
  TODA defesa: rate-limit/WAF, autenticação, validação de schema de input,
  sanitização, proteção contra abuso/DoS.

Confundir as duas é uma das falhas mais caras: um Redis/Postgres com porta
publicada, ou um endpoint `/internal/rpc` no mesmo servidor público.

## Procedimento (determinístico)

`check-api-surface-isolation.sh` reusa `.blindar/graph.json` (constrói se faltar):

1. **Serviço interno com porta publicada** (crit) — db/redis/mq/worker com
   `ports:` no compose. Deve usar só a rede interna.
2. **Bind em 0.0.0.0** em arquivo interno (crit) — restrinja a 127.0.0.1/rede.
3. **Endpoint externo de escrita sem validação de schema** (high) —
   zod/joi/pydantic/class-validator obrigatório na borda.
4. **Superfície externa sem rate-limit/WAF/helmet** (high) — proteção de borda.

## Output esperado

`.blindar/results/check-api-surface-isolation.json`. Findings crit → falha.

## Anti-padrões

- ❌ Postgres/Redis com `ports:` "só pra debug" — use rede interna + túnel.
- ❌ Um único servidor servindo rotas públicas e `/internal/*` juntas.
- ❌ Confiar em input externo sem validar schema.
- ❌ API externa sem rate-limit ("ninguém vai abusar").
