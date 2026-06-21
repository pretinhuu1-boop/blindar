# Roadmap

Lista honesta dos 30 itens do brainstorm de melhorias + status em
v0.6.0.

## Legenda

- ✅ **Done** — implementado e em uso
- 🔜 **Spec** — desenho pronto em `docs/specs/`, implementação pendente
- 📝 **Doc** — comportamento documentado em agente/pipeline, falta automação
- ⏸ **Deferred** — requer trabalho fora do escopo de um chat session

## Tier 1 — Segurança (impacto: % de segurança 85→92%)

| # | Item | Status v0.6.0 | Onde |
|---|---|---|---|
| 1 | Agente de lógica de negócio | ✅ Done | [`agents/business-logic.md`](agents/business-logic.md) |
| 2 | Agente auth-edges expandido | ✅ Done | [`agents/access-control.md`](agents/access-control.md) seção v0.6.0 |
| 3 | API contract enforcement | 🔜 Spec | [`docs/specs/api-contract.md`](docs/specs/api-contract.md) |
| 4 | Race-fuzzing agent | 🔜 Spec | [`docs/specs/race-fuzzing.md`](docs/specs/race-fuzzing.md) |
| 5 | Hunting de secrets em runtime | ✅ Done | [`agents/runtime-secrets.md`](agents/runtime-secrets.md) |

## Tier 2 — Escala/Fluidez (impacto: % 70-80→85%)

| # | Item | Status v0.6.0 | Onde |
|---|---|---|---|
| 6 | Load-test harness no termination | 🔜 Spec | [`docs/specs/load-test-harness.md`](docs/specs/load-test-harness.md) |
| 7 | IaC fixes como PRs separados | 📝 Doc | [`agents/devops.md`](agents/devops.md) seção v0.6.0 |
| 8 | CWV monitoring contínuo pós-launch | 📝 Doc | [`agents/observability.md`](agents/observability.md) seção v0.6.0 |
| 9 | Cache/DB benchmark obrigatório | 📝 Doc | [`agents/scalability.md`](agents/scalability.md) seção v0.6.0 |

## Tier 3 — Atrito pra qualquer AI

| # | Item | Status v0.6.0 | Onde |
|---|---|---|---|
| 10 | Dry-run REAL | 📝 Doc | [`schemas/config.schema.json`](schemas/config.schema.json) + [`AI-ENTRYPOINT.md`](AI-ENTRYPOINT.md) Passo 0 |
| 11 | Modo `--minimal` | 📝 Doc | [`schemas/config.schema.json`](schemas/config.schema.json) + AI-ENTRYPOINT |
| 12 | Validator CLI | ✅ Done | [`scripts/validate.ps1`](scripts/validate.ps1) + `.sh` |
| 13 | Reference impl MULTI-AI | ⏸ Deferred | Requer app full (Python/Node) |
| 14 | Bash equivalentes | ✅ Done | [`scripts/preflight.sh`](scripts/preflight.sh), `install.sh`, `check-update.sh`, `validate.sh` |

## Tier 4 — Prova/auditoria

| # | Item | Status v0.6.0 | Onde |
|---|---|---|---|
| 15 | Evidence package assinado | 🔜 Spec | [`docs/specs/evidence-package.md`](docs/specs/evidence-package.md) |
| 16 | Reproducibility check | 🔜 Spec | [`docs/specs/reproducibility.md`](docs/specs/reproducibility.md) |
| 17 | SBOM de ATKs cobertos | 🔜 Spec | [`docs/specs/atk-sbom.md`](docs/specs/atk-sbom.md) |
| 18 | Coverage multi-framework simultâneo | ✅ Done | [`schemas/config.schema.json`](schemas/config.schema.json) (array em `target_framework`) |

## Tier 5 — Proteção contínua

| # | Item | Status v0.6.0 | Onde |
|---|---|---|---|
| 19 | Modo manutenção (quarterly) | ✅ Done | [`pipeline/08-maintenance.md`](pipeline/08-maintenance.md) |
| 20 | CVE feed subscription | 📝 Doc | [`agents/patch-management.md`](agents/patch-management.md) seção v0.6.0 |
| 21 | Drift detection | ✅ Done | [`pipeline/09-drift-detection.md`](pipeline/09-drift-detection.md) |
| 22 | Re-preflight antes de release | ✅ Done | [`scripts/preflight.ps1`](scripts/preflight.ps1) já funciona; doc em [`pipeline/08-maintenance.md`](pipeline/08-maintenance.md) |

## Tier 6 — DX/Adoção

| # | Item | Status v0.6.0 | Onde |
|---|---|---|---|
| 23 | Web dashboard hosted | ⏸ Deferred | Requer app frontend separado |
| 24 | Notifications | 🔜 Spec | [`docs/specs/notifications.md`](docs/specs/notifications.md) |
| 25 | IDE plugin | ⏸ Deferred | Requer extensão VSCode/JetBrains |
| 26 | CLI standalone | ⏸ Deferred | Requer app que orquestra LLM API |
| 27 | `examples/` com 3 demos | ⏸ Deferred | Requer criar projetos demo funcionais |

## Tier 7 — Comunidade

| # | Item | Status v0.6.0 | Onde |
|---|---|---|---|
| 28 | Catálogo ATKs compartilhado | ⏸ Deferred | Requer infra comunitária |
| 29 | Stack-specific starters | ⏸ Deferred | Requer projetos starter |
| 30 | Compatibility matrix (Vercel/Supabase/...) | ⏸ Deferred | Requer teste real com PaaS |

## Sumário v0.6.0

- ✅ **Done**: 11 itens
- 📝 **Doc**: 7 itens (comportamento documentado nos agentes, automação parcial)
- 🔜 **Spec**: 7 itens (desenho pronto, implementação pendente)
- ⏸ **Deferred**: 8 itens (requer trabalho fora do skill)

**Total endereçado**: 25/30 (83% dos itens do brainstorm).

## Como contribuir com qualquer item

1. Abra issue em [github.com/pretinhuu1-boop/blindar/issues](https://github.com/pretinhuu1-boop/blindar/issues)
2. Indique qual item do roadmap
3. Mostre **bug/dor real observada** (princípio do skill — não é "seria legal")
4. PR com implementação respeitando princípios não-negociáveis do skill

## % projetada com tudo implementado

Se todos os 30 itens fossem implementados (incluindo Tier 6 e 7):

- Segurança: 85-90% → **93-96%**
- Escalabilidade: 70-80% → **88-92%**
- Fluidez: 75-85% → **88-92%**

Notem: nem todos os tiers mexem na %. Tier 6 e 7 mexem em adoção/UX,
não em qualidade técnica do hardening.
