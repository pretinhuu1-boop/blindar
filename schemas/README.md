# schemas/ — contratos JSON formais

Cada arquivo aqui define a forma exata da saída esperada de um agente ou
estado do skill. Permite que **qualquer AI** retorne JSON validável,
sem ambiguidade de formato entre execuções.

## Schemas de discovery (Fase 1)

| Schema | Agente que produz | Onde é consumido |
|---|---|---|
| `inventory.schema.json` | inventory | bootstrap do `sec.html` (endpoints tab) |
| `threat.schema.json` | threat-model | matrix de ATKs no `sec.html` |
| `arch.schema.json` | architecture | priorização de rounds + stacks.md lookup |

## Schemas de review (Fase 4)

| Schema | Agente | Consumo |
|---|---|---|
| `findings.schema.json` | adversarial-reviewer (4 lentes) | input do verify |
| `verdict.schema.json` | verify (default-refute) | filtro `isReal=true` → nova rodada |

## Schemas de estado (no projeto-alvo)

| Schema | Localização no projeto | Propósito |
|---|---|---|
| `state.schema.json` | `.blindar/state.json` | resumability determinística |
| `config.schema.json` | `.blindar/config.yml` | overrides de defaults |

## Como AIs usam

**Claude Code** — passa o schema via `agent(..., {schema: SCHEMA})`. Sistema
valida e força retry em mismatch.

**Outras AIs** — o agente humano-em-loop cola o schema no prompt + pede
"valide JSON contra o schema antes de retornar". Validação manual ou via
ferramenta externa (`ajv-cli`, `jsonschema` Python, etc.).

## Princípios

- **Draft-07 JSON Schema** (compatibilidade máxima)
- **`required` explícito** em todo objeto (sem campos opcionais escondidos)
- **`enum`** sempre que houver vocabulário fechado (severidade, categoria, etc.)
- **`additionalProperties: false`** **NÃO** usado por default — agents podem
  retornar campos extras úteis sem quebrar o schema
- Schemas versionados junto com o skill (mesma `VERSION`)

## Validar localmente

```powershell
# instalar ajv-cli (Node)
npm i -g ajv-cli ajv-formats

# validar um output
ajv validate -s schemas\inventory.schema.json -d output.json
```
