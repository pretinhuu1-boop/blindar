# Contrato `.blindar/` (no projeto-alvo)

Este documento define a estrutura que o skill mantém **dentro do projeto
sendo blindado** — NÃO dentro do próprio repo do skill.

## Localização

```
seu-projeto/
├── .blindar/              ← criado na primeira execução
│   ├── config.yml         ← overrides de defaults (opcional, humano edita)
│   ├── state.json         ← estado do ciclo (skill mantém)
│   ├── accept-risk.md     ← riscos aceitos (skill + humano)
│   ├── discovery/         ← outputs cached da Fase 1
│   │   ├── inventory.json
│   │   ├── threats.json
│   │   └── architecture.json
│   └── checkpoints/       ← snapshots por adversarial review
│       ├── round-10.json
│       └── round-20.json
├── sec.html               ← dashboard vivo (raiz)
├── docs/                  ← runbooks gerados
│   ├── incident-response.md
│   ├── key-rotation.md
│   ├── supply-chain.md
│   └── lgpd/              ← se projeto BR
└── ... (resto do projeto)
```

## Arquivos críticos

### `state.json`

Schema formal: [`schemas/state.schema.json`](schemas/state.schema.json).

Estado do ciclo. Permite resumability determinística — `Ctrl+C` deixa
isso intacto, próxima invocação lê e continua.

**Quem escreve**: skill, após cada round e ao mudar de fase.
**Quem lê**: skill, no início de cada invocação.
**Versionado em git?**: **NÃO** — adicione `.blindar/state.json` ao
`.gitignore` do projeto (mas commite `.blindar/config.yml`).

Exemplo:

```json
{
  "blindar_version": "0.5.0",
  "started_at": "2026-06-07T10:00:00Z",
  "last_updated": "2026-06-07T14:30:00Z",
  "phase": "rounds",
  "rounds_completed": 27,
  "rounds_since_last_adversarial": 7,
  "current_round": {
    "atk_id": "ATK-018",
    "agent": "access-control",
    "branch": "sec/r028-idempotency-key",
    "pr_number": 142,
    "started_at": "2026-06-07T14:25:00Z"
  },
  "termination_check": {
    "zero_crit_confirmed": false,
    "high_count_acknowledged": 5,
    "critical_categories_coverage_pct": 64,
    "runbooks_generated": ["incident-response.md"],
    "ci_green_streak": 2,
    "production_checklist_passed": false
  },
  "framework_target": "asvs-l2"
}
```

### `config.yml`

Schema formal: [`schemas/config.schema.json`](schemas/config.schema.json).

Overrides dos defaults do skill. **Tudo é opcional**.

**Quem escreve**: humano (criado vazio na primeira execução, ou copiado
do template).
**Quem lê**: skill, no início de cada invocação.
**Versionado em git?**: **SIM** — vira parte da config do repo.

Exemplo mínimo:

```yaml
# .blindar/config.yml
target_framework: asvs-l2
skip_agents:
  - frontend           # projeto CLI-only, sem frontend
  - frontend-performance
adversarial_cadence: 15  # mais espaçado pra projetos com CI lenta
```

Exemplo gerado pelo launcher v0.8:

```yaml
# .blindar/config.yml — gerado pela Fase 00 (launcher)
schema: blindar/config@v0.8
mode: auto                 # auto | supervised | chosen
selected_modules:          # números do menu (1..15)
  - 1
  - 2
  - 3
  - 5
  - 6
  - 8
  - 9
  - 10
  - 11
  - 12
  - 14
  - 15
project_type: saas         # saas|mvp|landing|ecom|api|mobile|cli|other
data_sensitivity: high     # high|medium|low
rigor: production          # production|compliance|mvp
target_framework: null     # null se rigor != compliance
ui_detected: true          # detectado em Fase 02, pode ajustar
db_detected: true
branch: main
launcher_completed_at: "2026-06-14T18:00:00Z"
```

**Campos v0.8 (todos opcionais — pipeline tem fallback)**:

| Campo | Quem preenche | Default | Efeito |
|---|---|---|---|
| `mode` | launcher | `auto` | Define se pausa entre rounds (supervised) ou só roda módulos escolhidos (chosen) |
| `selected_modules` | launcher | (rodar todos os 15) | Filtra agentes na Fase 04 e gates na Fase 06 |
| `project_type` | launcher | (sem default) | Influencia defaults de módulos no launcher |
| `data_sensitivity` | launcher | `medium` | Força módulo 8 (LGPD) se `high`/`medium` |
| `rigor` | launcher | `production` | `mvp` desliga módulo 13 por default |
| `ui_detected` | discovery | (detecta) | Liga módulos 3 e 10 por default |
| `db_detected` | discovery | (detecta) | Liga módulo 7 por default |

### `accept-risk.md`

Template: [`templates/accept-risk.md`](templates/accept-risk.md).

Riscos conscientemente aceitos. Quando skill encontra um ATK que está
documentado aqui como aceito, **não vira round**.

**Quem escreve**: humano (decisões) + skill (registra warns da Fase 5).
**Quem lê**: skill, ao priorizar gaps.
**Versionado em git?**: **SIM** — decisão auditável.

### `discovery/*.json`

Outputs cached da Fase 1, validados contra schemas. Reaproveitados em
invocações subsequentes pra não re-descobrir desnecessariamente.

**Invalidação**: se passou >30 dias ou se `arch.json.stack` diverge do
projeto atual, skill re-roda discovery.

### `checkpoints/round-N.json`

Snapshot do estado após cada adversarial review. Auditoria histórica —
permite responder "qual era o status quando rodamos a review N?".

## `.gitignore` recomendado pro projeto-alvo

```gitignore
# blindar — estado interno (volátil)
.blindar/state.json
.blindar/discovery/
.blindar/checkpoints/

# blindar — manter versionado
# .blindar/config.yml         (deixar — config do repo)
# .blindar/accept-risk.md     (deixar — auditoria)

# Cache do auto-update do skill (se rodando local)
.last-check
```

## Migração do estado antigo

Versões `< 0.5.0` colocavam `accept-risk.md` na raiz e não tinham
`state.json`. Migração:

```powershell
# Roda 1x no projeto-alvo após instalar skill v0.5.0+
mkdir .blindar
mv accept-risk.md .blindar/  # se existia na raiz
# state.json e config.yml são criados na próxima invocação
```

Skill detecta `accept-risk.md` na raiz e oferece migração automática
(ou roda manualmente o comando acima).

### Migração v0.7 → v0.8

**Nada a fazer**. Configs antigos (sem `mode` e `selected_modules`) rodam
como `mode: auto` + "todos os módulos" — preserva 100% do comportamento
v0.7. Skill detecta `.blindar/config.yml` sem campos v0.8 e:

- Se rodando interativo: chama launcher na próxima invocação pra atualizar
- Se rodando `--headless`: usa defaults sem perguntar

Pra forçar re-onboarding do launcher: `blindar --reset` (apaga `.blindar/`)
ou apenas remova manualmente `config.yml`.

## Garantias

- Skill **nunca** apaga `config.yml` ou `accept-risk.md` sem confirmação.
- Skill **pode** apagar `state.json` se detectar corrupção (vai pedir
  confirmação primeiro, com diff do que vai recriar).
- `discovery/` é cache — apagar não causa perda permanente (re-descobre).
- `checkpoints/` é auditoria — apagar perde histórico mas não bloqueia.
