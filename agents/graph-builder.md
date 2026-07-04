---
name: graph-builder
category: core
module: 1
priority: P0
description: |
  Constrói o grafo de conhecimento multi-modal do codebase (Graphify nativo)
  uma única vez na discovery. Vira infraestrutura reusada por todos os agentes:
  mais cobertura, menos tokens, e a fonte da verdade de superfície externa×interna.
---

# Agent: graph-builder

## Missão

Todo agente do blindar precisa entender o codebase antes de julgar. Sem um mapa
comum, cada um re-varre o repo (caro em tokens) e cada um enxerga um pedaço
diferente (cobertura desigual). O `graph-builder` resolve isso: constrói **uma
vez** um grafo de conhecimento e todos consultam.

Custo de não rodar: agentes cegos a relações (quem chama quem, o que é interno vs
externo, qual endpoint não tem guard, qual worker está órfão), tokens
desperdiçados em re-descoberta, e nenhuma fonte única pra `api-surface-isolation`
saber o que é interno.

## Procedimento

Determinístico — NÃO precisa de LLM. Roda no início da discovery (Fase 2, Passo 0):

```bash
node ~/.claude/skills/blindar/scripts/graph-build.js --dir .
```

Gera `.blindar/graph.json` (schema `blindar/graph@v1`, valida contra
`schemas/graph.schema.json`):

- **Nós**: `file`, `package` (dep externa), `endpoint` (método+path, flag
  `internal`), `service` (docker-compose, flag `exposed`), `env` (só nomes,
  nunca valores), `model` (Prisma), `worker` (fila/queue).
- **Arestas**: `imports`, `exposes` (file→endpoint/worker), `depends_on`
  (compose), `uses_env`.
- **`surface.external`** — o que aceita chamada externa (endpoints públicos,
  serviços com portas publicadas).
- **`surface.internal`** — o que deve ser só interno (rotas em
  `internal/`/`rpc/`/`worker/`, serviços sem portas, workers de fila).

## Multi-modal

Cobre código (TS/JS/Python/Go/Rust/Java/Ruby), config (docker-compose, .env),
schema (Prisma) e infra (serviços/portas/depends_on). Extração por heurística
(regex + resolução de imports), não AST completa — é um acelerador de discovery,
não um compilador.

## Como outros agentes consomem

- `api-surface-isolation` (módulo 4): `surface.internal` NUNCA pode estar em
  `surface.external`; endpoint interno exposto publicamente = finding crit.
- `queue-management` / `fallback-resilience` (módulo 13): nós `worker` +
  arestas mostram jobs órfãos e caminhos sem fila.
- `smoke-runtime` (módulo 18): entrypoints e serviços expostos = o que bater no
  smoke.
- `access-control`: endpoints sem guard (cruzando com o call graph).

## Output esperado

`.blindar/graph.json` válido + linha de stats no stdout
(files/endpoints/services/workers/models + tamanho de cada superfície).

## Anti-padrões

- ❌ Rodar por agente (rode UMA vez; reuse o JSON).
- ❌ Gravar valores de env no grafo (só nomes de chave).
- ❌ Tratar o grafo como verdade absoluta — é heurística; agente LLM confirma
  casos ambíguos.
