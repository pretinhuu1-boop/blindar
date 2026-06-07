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

## Garantias

- Skill **nunca** apaga `config.yml` ou `accept-risk.md` sem confirmação.
- Skill **pode** apagar `state.json` se detectar corrupção (vai pedir
  confirmação primeiro, com diff do que vai recriar).
- `discovery/` é cache — apagar não causa perda permanente (re-descobre).
- `checkpoints/` é auditoria — apagar perde histórico mas não bloqueia.
