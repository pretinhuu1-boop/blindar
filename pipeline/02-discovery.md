# Fase 1 — Discovery

**Duração**: ~3 min (3 agentes paralelos)

## Objetivo

Mapear superfície de ataque, catalogar ameaças aplicáveis, classificar a
arquitetura. Tudo paralelo.

## Execução

Spawn via Workflow:

```javascript
phase('Discovery')
const [inventory, threats, arch] = await parallel([
  () => agent(
    'Map attack surface: HTTP endpoints (path+method+auth), CLI, external API ' +
    'calls (LLM/payment/OAuth), daemons, workers. Return JSON.',
    { agentType: 'general-purpose', schema: INVENTORY_SCHEMA }
  ),
  () => agent(
    'List applicable ATKs from 2024-2026 landscape across web_api/auth_session/' +
    'llm_agent/supply_chain/cve_deps/frontend/infra/compliance. Mark gap vs n/a. ' +
    'JSON catalog.',
    { agentType: 'general-purpose', schema: THREAT_SCHEMA }
  ),
  () => agent(
    'Classify architecture: SPA/SSR, mono/micro, queue, DB, deploy target, ' +
    'shared resources, daemons. JSON.',
    { agentType: 'general-purpose', schema: ARCH_SCHEMA }
  ),
])
```

## Agentes (todos `general-purpose`)

1. **inventory** — superfície de ataque (endpoints, CLI, externos, daemons)
2. **threat-model** — ATKs aplicáveis do landscape 2024-2026
3. **architecture** — classifica forma do sistema

## Adaptação por stack

Discovery agent identifica stack e marca categorias extras pra adicionar na
matrix da Fase 2. Ver [`stacks.md`](../stacks.md).

## Saída

Três JSONs validados por schema (`schemas/` quando criado).
Alimentam a Fase 2 (bootstrap do `sec.html`).
