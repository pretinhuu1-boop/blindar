# Fase 2 — Discovery

**Duração**: ~3 min (3 agentes paralelos)

## Objetivo

Mapear superfície de ataque, catalogar ameaças aplicáveis, classificar a
arquitetura. Tudo paralelo.

## Passo 0 — Grafo de conhecimento (determinístico, roda ANTES dos agentes)

Antes de gastar tokens com LLM, construa o grafo multi-modal do codebase UMA
vez. Ele é reusado por TODOS os agentes desta fase e das seguintes → mais
cobertura (call graph, data-flow, fronteira interno×externo) e menos tokens
(ninguém re-varre o repo).

```bash
node ~/.claude/skills/blindar/scripts/graph-build.js --dir .
# → .blindar/graph.json  (nós: file/package/endpoint/service/env/model/worker;
#   arestas: imports/exposes/depends_on/uses_env; surface.external × surface.internal)
```

Os agentes de discovery abaixo recebem `.blindar/graph.json` como contexto —
não devem re-descobrir endpoints/serviços do zero, só interpretar e enriquecer.
`surface.external` (aceita chamada externa) vs `surface.internal` (só interno)
alimenta o agente `api-surface-isolation` (módulo 4) diretamente.

## Execução

Spawn via Workflow (todos recebem o grafo como evidência inicial):

```javascript
phase('Discovery')
const graph = JSON.parse(readFileSync('.blindar/graph.json','utf8'))
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
