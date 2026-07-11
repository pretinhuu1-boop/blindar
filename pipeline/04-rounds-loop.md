# Fase 4 — Loop de rounds

**Duração**: até termination (ver `SKILL.md`)

## Objetivo

Fechar gaps da matrix, um por vez, cada um virando um PR mergeado.

## Gate obrigatório no fim de cada onda (v0.34+)

**Antes de fechar QUALQUER onda**, invocar o `wave-guardian`:

```bash
WAVE_NUMBER=<N> \
WAVE_AGENTS="<lista,csv>" \
MIN_COVERAGE_PCT=90 \
bash templates/checks/check-wave-guardian.sh
```

Decisão:
- **Exit 0 (PASS)**: gera `wave-N-report.md`, abre checkpoint de merge, segue
- **Exit 1 (BLOCKED)**: lê `.blindar/wave-<N>-guardian.md`, corrige causas, re-roda blindar-run + guardian. **NÃO feche a onda sem PASS.**

Pré-requisito: `bash scripts/blindar-run.sh --strict --module <ids-da-onda>`
deve ter rodado antes — guardian valida o `.blindar/run-report.json` gerado por ele.

**Anti-padrão**: rodar guardian, dar BLOCK, e fechar a onda mesmo assim. Se você
precisa fechar com débito, registre em `.blindar/debt.md` E reduza scope da
onda — não mascare o guardian.


## Filtragem por módulo selecionado (v0.8+)

**ANTES de pickar um gap**, consultar `pipeline/MODULE-MAP.json`:

```
const map = readJSON("pipeline/MODULE-MAP.json")
const config = readYAML(".blindar/config.yml")
const selected = config.selected_modules || [1..15]  // fallback: tudo

const allowedAgents = Object.entries(map.modules)
  .filter(([id]) => selected.includes(Number(id)))
  .flatMap(([, m]) => m.agents)
```

Cada round só roda se o agente que cobriria o gap está em `allowedAgents`.
Gap fora de módulo selecionado fica **pulado com log** (não é finding, não
quebra termination):

```
[round 23] skipped gap "XSS-DOM-injection" — agent 'frontend' not in
  selected_modules (module 3 OFF)
```

Se TODOS os módulos cobrindo um gap estiverem OFF, marcar gap como `n/a`
no `sec.html` com tag `skipped-by-user-selection`.

## Para cada round

1. **Pick** — highest-severity gap do matrix **cujo agente está em allowedAgents**
2. **Spawn** — agente especialista (resolvido via MODULE-MAP.json)
3. **Characterization test primeiro (código legado)** — se o trecho a blindar
   NÃO tem teste cobrindo o comportamento atual, escreva um teste que
   documenta o que ele faz HOJE (mesmo que "errado") ANTES de mudar. Ache o
   *seam* (ponto de alteração sem editar in-loco) e prefira **sprout/wrap** a
   reescrever método grande. Ver [`docs/book-insights.md`](../docs/book-insights.md)
   § Feathers. Isso estende "N/A vira teste de regressão" pra
   "comportamento pré-existente vira teste antes de tocar".
4. **Implement** — ≤ 80 LOC + teste real (≥ 3 asserts) + grep estático
5. **Update** — `sec.html`: ATK gap→covered, matrix recalc, version++
6. **Local check** — suite verde + type-check verde
7. **Commit** — branch `sec/<round-id>-<slug>` + template message
8. **Push + CI** — aguardar verde (sem `--no-verify`)
9. **Merge** — `gh pr merge --squash --delete-branch`
10. **Next**

A cada 10 rounds completos: **Fase 4** (adversarial review) automaticamente.

## Modo de execução (v0.8+)

Comportamento depende de `config.mode`:

| Mode | Comportamento |
|---|---|
| `auto` | Loop contínuo sem pausa. Roda até termination. |
| `supervised` | Após cada ROUND, pausa: "round X concluído. Próximo? (s/n)". Em `n` salva estado e para. |
| `chosen` | Roda só módulos em selected_modules. NÃO entra em loop infinito — termina quando todos os módulos selecionados estão `covered` ou `n/a`. |

## Roster completo de agentes

**Fonte da verdade**: [`pipeline/MODULE-MAP.json`](MODULE-MAP.json). Pipeline lê esse JSON
em tempo de execução pra resolver agentes por módulo selecionado.

Versão atual: **116 agentes em v0.47** distribuídos em 19 módulos numerados.
Para a tabela visual completa, ver [`SKILL.md`](../SKILL.md) seção "Menu de
módulos numerados". A filtragem real respeita `config.selected_modules` ∩
`MODULE-MAP[id].agents`.

## Quality gates por round

| Gate | Verificação | Bloqueia |
|---|---|---|
| Suite | pytest/vitest/etc verdes após cada round | merge |
| CI | todos jobs verde | merge |
| sec.html | commit junto com código do round | commit |
| Test real | ≥ 3 assertions cobrindo happy + edge + attack | round |
| Guard estático | grep que falha se defesa regredir | round |
| Branch | 1 PR/round, squash, branch deletada | sempre |

## Template de PR

Ver [`templates/pr-message.md`](../templates/pr-message.md).

## Anti-padrões (NUNCA)

- PR > 200 LOC ou > 5 arquivos → quebra em 2 rounds
- Implementação sem teste
- `sec.html` sem código mergeado
- Refactor durante hardening (PR próprio)
- Defesa nova quebrando teste antigo (refletir, ajustar contrato, NÃO silenciar)
- CI vermelha mergeada
- Schema `sec.html` mudando entre rounds
