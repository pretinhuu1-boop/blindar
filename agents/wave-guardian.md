---
name: wave-guardian
category: meta
module: 15
priority: P0
description: |
  Gate obrigatório no final de cada onda do rounds-loop. Roda o orquestrador
  determinístico contra os módulos da onda, lê run-report.json, valida
  thresholds. Bloqueia merge da onda se algo errored, failed crit, ou
  deferred não-coberto. Sem este gate, ondas podem fechar com gaps invisíveis.
---

# Agent: wave-guardian

## Missão

Garantir que toda onda do rounds-loop só fecha quando o **orquestrador
determinístico** (`scripts/blindar-run.sh`) confirma que:

1. Nenhum agente da onda deu `errored`
2. Nenhum `failed` com severidade `crit`
3. `deferred` (playbook-only) foram **explicitamente executados** nesta onda
4. `coverage_pct` ≥ threshold (default 90%)

Esta é a contraparte automática do "Claude precisa rodar tudo" — aqui o
**script** confirma, não confiança no LLM.

## Quando rodar

- **Sempre como último passo de cada onda** do `pipeline/04-rounds-loop.md`
- **Antes do checkpoint de merge** — bloqueia se gate falha
- **Antes de gerar `wave-N-report.md`** — o report cita o gate result

## Inputs

- `selected_modules` (da onda atual, do config.yml)
- `wave_number` (1, 2, 3...)
- `wave_agents` (lista declarada de agentes que a onda planejou rodar)
- `min_coverage_pct` (opcional, default 90)

## Procedimento determinístico

```bash
# 1. Rodar orquestrador no escopo da onda
bash scripts/blindar-run.sh --strict --module $(echo "$SELECTED_MODULES" | tr ' ' ',')

# 2. Capturar exit code
GUARDIAN_EXIT=$?

# 3. Rodar validador determinístico
bash templates/checks/check-wave-guardian.sh
```

## Decisão

| run-report condition | wave-guardian decision |
|---|---|
| `errored > 0` | **BLOCK** — bugs em scripts blindar, fix antes de mergear |
| `failed > 0` com severity crit | **BLOCK** — onda introduziu/manteve crit |
| `deferred > 0` AND não coberto manualmente | **BLOCK** — Claude pulou playbook |
| `coverage_pct < 90` | **WARN** — registra mas não bloqueia (configurável) |
| Tudo OK | **PASS** — onda pode fechar |

## Output

`wave-<N>-guardian.md` no projeto:

```markdown
# Wave N Guardian Report

- Ran at: <timestamp>
- Modules: <list>
- Coverage: 92%
- Passed: 18 / Failed: 0 / Skipped: 3 / Deferred: 0 / Errored: 0
- **Status: PASS** ✅

Onda pode fechar.
```

Ou em caso de block:

```markdown
# Wave N Guardian Report

- **Status: BLOCKED** ❌
- Reason: 1 errored, 2 deferred não-cobertos

## Errored
- check-tenant-isolation-tests.sh — exit 2 (path issue)

## Deferred não-cobertos
- adversarial-reviewer (sem ANTHROPIC_API_KEY OU sem playbook executado)
- pentest (idem)

## Ação requerida
Resolver os pontos acima antes de re-rodar a onda.
```

## Integração com rounds-loop

Editar `pipeline/04-rounds-loop.md` para incluir no final de cada onda:

```markdown
### Wave N: gate final (OBRIGATÓRIO)

Antes de fechar a onda:
1. Invocar `wave-guardian` agent
2. Se BLOCK: NÃO fecha. Gera plano de correção e re-executa.
3. Se PASS: gera `wave-N-report.md` + checkpoint de merge.
```

## Anti-padrões

- ❌ Pular o guardian "porque achei que rodei tudo"
- ❌ Ignorar `deferred` (significa que playbook não foi executado)
- ❌ Setar `min_coverage_pct=0` pra burlar
- ❌ Comitar wave-N-report.md com status PASS quando guardian deu BLOCK
- ❌ Editar manualmente o run-report.json
