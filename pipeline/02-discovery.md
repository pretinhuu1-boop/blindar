# Fase 2 — Discovery

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

## Detecção de capabilities do projeto (v0.8+)

Discovery agent também marca flags consumidas pelo MODULE-MAP:

```bash
# UI detectada?
ui_detected = exists(package.json com react|vue|svelte|next|nuxt|astro)
              OR exists(index.html)
              OR exists(public/)

# DB detectado?
db_detected = exists(.env* com DATABASE_URL|DB_HOST|POSTGRES|MYSQL|MONGO)
              OR exists(prisma/schema.prisma)
              OR exists(drizzle.config.*)
              OR exists(migrations/) OR exists(db/migrate/)

# API detectada?
api_detected = exists(routes/) OR exists(api/) OR exists(controllers/)
               OR rg("app\.(get|post|put|delete)|router\.(get|post)")
```

Essas flags vão pra `.blindar/config.yml` (atualiza `ui_detected`, `db_detected`)
e são usadas pelo `pipeline/MODULE-MAP.json` pra resolver quais módulos
ficam ON por default.

## Saída

Três JSONs validados por schema (`schemas/` quando criado) + atualização do
`.blindar/config.yml` com flags de detecção.

Alimentam a Fase 2 (bootstrap do `sec.html`) e a Fase 3 (rounds-loop), que
filtra agentes por `config.selected_modules` ∩ `MODULE-MAP[module].agents`.
