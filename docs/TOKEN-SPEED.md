# Token, velocidade e escala do próprio blindar (v0.45)

Como o blindar mantém custo baixo e velocidade alta mesmo com ~100 agentes.

## 1. Determinístico-primeiro (o maior ganho de token)

O orquestrador resolve cada agente assim: se existe `check-<agente>.sh`
(determinístico, zero LLM), roda ELE; só cai pra `check-<agente>.api.sh`
(Claude API) se não houver determinístico. Ou seja, **grep/AST antes de LLM**.
A camada determinística é a maioria dos checks e custa ~0 token.

Regra ao adicionar cobertura: se dá pra detectar com regex/AST/comando, é `.sh`.
Só use `.api.sh` quando exige julgamento real (arquitetura, compliance, RAG).

## 2. Grafo construído 1× e reusado

`graph-build.js` roda uma vez na discovery e grava `.blindar/graph.json`. Todos
os agentes consultam esse arquivo em vez de re-varrer o repo. N agentes × 1
varredura, não N varreduras. Menos I/O, menos tokens (o grafo já resume a
superfície pro agente LLM).

## 3. Módulos pesados são lazy (self-skip)

Smoke, pentest ativo, load-test e recon só fazem trabalho quando têm alvo:

| Módulo | Só roda se |
|---|---|
| 18 smoke | há Dockerfile/compose OU `--url` |
| 19 pentest-active | há `.accept-authorization` + `--target` |
| load-test | há `--url` |
| 17 attack-recon | opt-in + URL |

Sem o gatilho, emitem `skipped` em milissegundos. Nada de custo "por garantia".

## 4. Governor de tokens (por agente)

`_token_governor.sh` casa o modelo ao stake de cada agente:

| Tier | Modelo (standard) | Agentes |
|---|---|---|
| triage | Haiku | exploratório, o default |
| analysis | Sonnet | proactive-analysis, solution-architect, rag-quality |
| security | Opus | architect, adversarial, regulatory-mapper, vector-db |
| strategic | Opus (Fable só com BLINDAR_ALLOW_FABLE) | pentest profundo |

Presets: `BLINDAR_BUDGET=tight|standard|smart|premium`. `smart` sobe a dúvida
pra Sonnet (nunca Haiku) e mantém crítico em Opus. Piso: `BLINDAR_MIN_MODEL`.
Override por agente: `BLINDAR_TIER_<AGENTE>=...`. Cache de prompt automático em
system > ~1024 tokens (90% off). Hard cap: `BLINDAR_MAX_USD_PER_RUN` (default $2).
Telemetria em `.blindar/cost.log`.

## 5. Paralelismo

`blindar-run.sh --parallel auto` roda os checks determinísticos em paralelo
(xargs -P por CPU). Determinísticos são independentes e sem estado compartilhado.

## Resumo

Determinístico-primeiro + grafo reusado + lazy nos pesados + governor por stake
= cobertura de ~100 agentes sem estourar custo nem tempo. A regra de ouro:
**gaste LLM só onde exige julgamento; todo o resto é determinístico e barato.**
