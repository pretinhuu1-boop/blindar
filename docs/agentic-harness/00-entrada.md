---
name: agentic-harness
description: >
  Cria uma Claude Code Skill nova no padrão agentic-harness — o molde destilado
  do blindar. Combina playbooks markdown (julgamento do LLM) + checks
  determinísticos shell (validação objetiva) + wrappers de API estruturados
  (JSON forçado por tool_use) + wrappers de scanner externo (fallback gracioso)
  + orquestrador único paralelizado + gate determinístico + schema validado em
  runtime + saída SARIF + CLI Node zero-deps. Objetivo: quando a skill é
  invocada, TUDO executa, com cobertura mensurável e exit code claro — sem
  depender do LLM lembrar de fazer os passos. Use quando for criar uma skill
  nova, ou quando quiser auditar uma skill existente contra o padrão.
version: 1.0.0
---

# agentic-harness — molde para criar skills

Este é o padrão arquitetural extraído de ~50 versões do `blindar`. Ele existe
para resolver um problema específico:

> Uma skill que depende do LLM lembrar de executar cada passo **não tem
> cobertura** — tem sorte. O padrão troca diligência por determinismo.

`blindar` e `ancorar` são instâncias deste molde. Esta skill é o molde.

## Primeiro passo: PERGUNTE antes de gerar qualquer arquivo

Não crie nada antes de ter as 5 respostas:

1. **Nome da skill** (kebab-case — ex: `auditor-design`, `migrate-stack`)
2. **Propósito em 1 frase** (ex: "audita design system pra consistência de tokens")
3. **3–5 triggers naturais** — frases que o operador diria para ativar
4. **3–5 agentes iniciais** que fazem sentido para o propósito
5. **Categorização de cada agente** — ele é melhor como:
   - `.sh` determinístico (validação objetiva, grep/parse),
   - `.api.sh` wrapper de API (precisa de julgamento), ou
   - wrapper de scanner externo já existente (Semgrep/OSV/Trivy/Gitleaks)?

Substituições no resto da referência: `<NOME>` → nome kebab-case, `<PROPÓSITO>`
→ a frase única, `<NS>` → namespace curto para schemas.

## Referência — carregue só o que a etapa exige

Não leia tudo de uma vez. Cada arquivo é autocontido:

| Arquivo | Carregue quando for... |
|---|---|
| [`reference/01-estrutura-e-agentes.md`](reference/01-estrutura-e-agentes.md) | montar a árvore de pastas, o frontmatter do `SKILL.md`, o mandato imperativo, os agentes e o `MODULE-MAP.json` |
| [`reference/02-checks.md`](reference/02-checks.md) | escrever um check — os 3 padrões (determinístico, `.api.sh`, wrapper de scanner) |
| [`reference/03-libs.md`](reference/03-libs.md) | escrever `_lib.sh` e `_api_wrapper.sh` (esqueletos obrigatórios) |
| [`reference/04-orquestrador.md`](reference/04-orquestrador.md) | escrever `scripts/<NOME>-run.sh` — paralelização, modos, agregação |
| [`reference/05-tooling.md`](reference/05-tooling.md) | adicionar SARIF, validador de schema, schemas, auto-fix ou o CLI Node |
| [`reference/06-garantias-e-licoes.md`](reference/06-garantias-e-licoes.md) | fechar a skill — garantias, bugs a evitar, testes, proactive-analysis, wave-guardian |

## As 6 garantias que definem o padrão

Se a skill nova não tiver estas, ela não é agentic-harness. As 21 completas
estão em `reference/06-garantias-e-licoes.md`.

1. **Entrypoint único** — o `SKILL.md` MANDA que a primeira ação seja
   `bash scripts/<NOME>-run.sh`. Não sugere: manda.
2. **Cobertura mensurável** — o orquestrador emite `run-report.json` com
   `coverage_pct`. Sem número, não há cobertura.
3. **Skip silencioso é impossível** — todo skip vira `deferred` explícito no
   relatório. Skip por ferramenta ausente ≠ aprovação, e o consumidor do
   resultado precisa conseguir distinguir os dois.
4. **Exit codes claros** — `0`=PASS, `1`=CONDITIONAL, `2`=FAIL, `3`=STRICT-FAIL,
   `4`=ERRORED.
5. **Fallback gracioso** — `rg` ausente → `grep -rE`; `jq` ausente → Node; API
   key ausente → `skipped`, nunca `fail`. Ferramenta opcional não reprova.
6. **Schema versionado E validado em runtime** — todo JSON traz
   `"schema": "<NS>/X@v1"` e o `validate-schemas.js` confere. Schema versionado
   sem validador é decoração.

## As 5 armadilhas mais caras

A lista completa (27 bugs já pagos) está em
`reference/06-garantias-e-licoes.md`. Estas cinco custaram mais caro:

- `set -uo pipefail` **sem** `-e` no `_lib.sh`. Com `-e`, `rg | sort` mata o
  script porque `rg` sem match sai 1.
- `trap ERR` sem `set -e` é **código morto**. Não cole por hábito.
- Globs soltos no `rg` viram **caminhos**, não filtros. Sem `-g`, todos ficam
  inválidos, o `rg` não varre nada, sai 2 e o check **passa sempre**. O fallback
  de `grep` aceita a forma solta, então o bug só aparece com ripgrep instalado —
  ou seja, em produção e não no teste.
- Heurística "o arquivo menciona X, logo tem guard" é frágil: um comentário
  casa. Exija X como **string literal** ou allowlist.
- `.<NOME>/` e `.git` fora dos `IGNORE_GLOBS` → a skill se auto-detecta e
  reporta a si mesma.

## Regra de encerramento

Todo check gate-ável precisa de um **par de fixtures** — um que dispara
(`failed`) e um que cala (`passed`) — registrado no self-test. Sem o par, o
check é volume, não cobertura. Um check sem par verificado nunca deve mergear.

## Origem

Destilado do `blindar` (repo `Documents/Axial/Blidar`, v0.50+). O `blindar`
audita código; o `ancorar` audita operação; ambos seguem este molde. Ao evoluir
o padrão aqui, considere se a lição volta para eles.
