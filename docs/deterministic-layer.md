# Deterministic Layer (v0.22+)

## Por que existe

Até v0.21, blindar era 100% **prescrição via LLM**: cada agente era um
arquivo `.md` com greps, anti-padrões e regras que **Claude lê e segue**.
Funciona, mas tem 2 limitações:

1. **Não é garantido**: Claude pode esquecer, pular, ficar sem contexto
2. **Não é auditável**: não dá pra provar "esse check rodou e passou"

A camada determinística resolve isso convertendo cada agente em **um
script shell executável** + CI workflow + branch protection. Resultado:

- ✅ Roda em CI independente da diligência da IA
- ✅ Resultado é `exit 0` / `exit 1` (mensurável)
- ✅ Bloqueia merge via branch protection
- ✅ Output em JSON estruturado pra agregação

## Arquitetura

```
[Claude com blindar]                  [Camada determinística]
   ↓ planeja + escreve código              ↓ valida + bloqueia
   agents/*.md                          templates/checks/*.sh
   (72 agentes)                         (10 representativos em v0.22)
   ↓                                    ↓
   prescreve regras                     materializa em script
   ↓                                    ↓
   sugere fixes                         scripts/blindar/*.sh (no projeto)
                                        ↓
                                        .github/workflows/blindar.yml
                                        ↓
                                        branch protection
                                        ↓
                                        merge IMPOSSÍVEL sem aprovação
```

## Quem faz o quê

| Camada | Responsabilidade |
|---|---|
| **Claude com blindar (skill)** | Decisão estratégica, escrever código novo, sugerir refactor, gerar artefatos (relatórios HTML, docs, Postman collection) |
| **Scripts determinísticos** | Validar que regras foram seguidas, bloquear merge, emitir JSON auditável |
| **CI workflow** | Rodar scripts em pull_request + push; postar comentário com resumo; falhar build se status != passed |
| **Branch protection** | Impedir merge sem todos os status checks verdes |
| **Termination calculator** | Decisão MATEMÁTICA de "release pronta?" — 0 crit + ≤2 high accepted + coverage + CI streak |

## Estrutura no projeto-alvo (após instalar)

```
projeto-alvo/
├── scripts/blindar/
│   ├── _lib.sh                          # utilities compartilhadas
│   ├── check-secrets.sh                 # → materializa runtime-secrets agent
│   ├── check-mock-killer.sh             # → materializa mock-killer agent
│   ├── check-config-externalization.sh
│   ├── check-deps-audit.sh
│   ├── check-prisma-schema.sh
│   ├── check-payments.sh
│   ├── check-file-uploads.sh
│   ├── check-tenant-isolation.sh
│   ├── run-all.sh                       # orquestrador master
│   └── check-termination.sh             # decisão de release
│
├── .github/workflows/
│   └── blindar.yml                      # CI workflow obrigatório
│
├── .husky/
│   ├── pre-commit                       # fast checks (secrets + mock)
│   └── pre-push                         # full checks + termination
│
└── .blindar/
    ├── accept-risk.md                   # highs aceitos conscientemente
    └── results/
        ├── aggregate.json               # consolidado
        ├── secrets.json
        ├── mock-killer.json
        └── ... (1 por check rodado)
```

## Como instalar no projeto

```bash
cd seu-projeto
bash ~/.claude/skills/blindar/scripts/install-deterministic-checks.sh
```

O instalador:
1. Copia os 8 check scripts pra `scripts/blindar/`
2. Copia o CI workflow pra `.github/workflows/blindar.yml`
3. Copia hooks Husky se Husky já configurado
4. Cria `.blindar/accept-risk.md` template se não existir
5. Lista dependências externas faltantes (gitleaks, rg, jq)

## Formato JSON dos resultados

Cada check gera `.blindar/results/<agent>.json`:

```json
{
  "schema": "blindar/check-result@v1",
  "agent": "mock-killer",
  "ran_at": "2026-06-14T20:00:00Z",
  "git_sha": "abc1234",
  "status": "failed",
  "exit_code": 1,
  "duration_sec": 2,
  "findings_count": 3,
  "findings": [
    {
      "severity": "crit",
      "message": "Botão sem handler real: onClick={() => {}}",
      "file": "src/components/Submit.tsx",
      "line": "42"
    }
  ]
}
```

`run-all.sh` agrega tudo em `aggregate.json`:

```json
{
  "schema": "blindar/aggregate@v1",
  "ran_at": "2026-06-14T20:00:05Z",
  "duration_sec": 12,
  "total_checks": 8,
  "passed": 6,
  "failed": 2,
  "skipped": 0,
  "total_findings": 11,
  "findings_by_severity": {
    "crit": 2,
    "high": 5,
    "med": 3,
    "low": 1
  },
  "results": [...]
}
```

## Termination check

`check-termination.sh` lê aggregate e decide:

| Critério | Valor padrão | Override env var |
|---|---|---|
| Max crits abertos | 0 | `MAX_CRIT` |
| Max highs sem accept-risk | 2 | `MAX_HIGH_ACCEPTED` |
| Min coverage % | 80 | `MIN_COVERAGE_PCT` |
| Min CI green streak | 3 runs | `MIN_CI_GREEN_STREAK` |

Exit codes:
- `0` — release liberada
- `1` — crit aberto
- `2` — high > 2 sem accept-risk
- `3` — coverage insuficiente
- `4` — CI streak insuficiente

## Aceitar high conscientemente

Edite `.blindar/accept-risk.md`:

```markdown
- [x] **api-design** — endpoint /admin/audit-log usa offset pagination em vez de cursor
  - ADR: docs/adr/0008-admin-uses-offset.md
  - Razão: admin precisa de "página 47", cursor não atende
  - Quando reavaliar: 2027-01
```

`[x]` marca como aceito. `check-termination.sh` conta apenas o que está
marcado como **HIGH não-aceito**.

## Branch protection (configurar 1x no GitHub)

```
Settings → Branches → main → Add rule:
  ☑ Require pull request before merging
  ☑ Require status checks to pass before merging
    Status checks required:
      - blindar-checks
      - ci/lint
      - ci/type-check
      - ci/test
  ☑ Require branches to be up to date
  ☑ Do not allow bypassing the above settings
```

Merge **literalmente impossível** sem todos verdes. Nem admin bypassa
(com a última opção marcada).

## Comparação: prescrição vs determinístico

| Aspecto | v0.21 (prescrição) | v0.22 (determinístico) |
|---|---|---|
| Cobertura | "Claude deve fazer X" | Script executa X |
| Auditoria | "Claude disse que rodou" | JSON com timestamp + git_sha |
| Bloqueio | "Anti-padrão documentado" | CI falha + branch protection |
| Idempotência | Variável (LLM) | Determinística (script) |
| Velocidade | Depende do contexto | Segundos |
| Falso negativo | Possível (Claude pula) | Quando regex incompleta |
| Falso positivo | Possível (Claude superinterpretar) | Possível (regex genérica) — mitigado via intelligence.yml |

## Quando blindar prescrição AINDA importa

A camada determinística NÃO substitui Claude — complementa:

| Tarefa | Camada determinística | Claude (blindar) |
|---|---|---|
| "Tem secret em código?" | ✅ gitleaks | — |
| "Há queries sem tenant_id?" | ✅ grep | — |
| "Como reorganizar essa pasta?" | — | ✅ architect agent |
| "Refatorar pra optimistic locking" | — | ✅ db-architect agent |
| "Gerar manual do cliente" | — | ✅ delivery-bundle + client-report |
| "Migration zero-downtime pra trocar coluna" | — | ✅ db-architect (plan + write SQL) |
| "Validar que migration roda" | ✅ Prisma migrate dev --dry-run | — |
| "Bloquear merge se algo crítico" | ✅ CI + branch protection | — |

## Próximos passos (após v0.22)

- Materializar mais 60+ scripts (1 por agente faltante)
- Test suite do blindar (`tests/blindar/` com projetos fixture)
- CLI standalone `npx blindar check` (sem precisar de bash)
- Visual regression integration (Chromatic/Percy)
- Performance budget enforcement (size-limit)
- Lighthouse CI integration
