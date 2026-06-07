# Fase 7 — Maintenance mode (opcional, contínuo)

**Cadência sugerida**: trimestral (a cada 3 meses).
**Trigger**: scheduled cron OU pre-release manual OU CVE crítica detectada.

⚠ **Status v0.6.0**: nova fase, **opt-in**. Não roda automaticamente após
Fase 6. Operador configura schedule.

## Objetivo

"Pronto pra produção" da Fase 6 **decai com o tempo**:

- Deps ficam stale
- CVEs novas afetam libs que eram seguras na release
- Padrões da indústria evoluem (Web Vitals mudou FID → INP em 2024)
- Defesas removidas em PRs futuros (drift)

Maintenance mode roda **um ciclo curto** que detecta drift e fecha gaps.

## Como ativar

### Opção 1: GitHub Actions cron

Adicionar `.github/workflows/blindar-maintenance.yml` no projeto-alvo:

```yaml
name: blindar-maintenance
on:
  schedule:
    - cron: '0 9 1 */3 *'   # 09:00 UTC, dia 1, a cada 3 meses
  workflow_dispatch:         # permite trigger manual
jobs:
  maintenance:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Run blindar in maintenance mode
        env:
          BLINDAR_MODE: maintenance
        run: |
          # Aciona AI que tem acesso ao repo
          # (implementação específica do ambiente de cada time)
          echo "Trigger blindar maintenance via webhook/API"
```

### Opção 2: Pre-release hook

Antes de `gh release create`, rodar localmente:

```powershell
# No projeto-alvo
& "$env:USERPROFILE\.claude\skills\blindar\scripts\preflight.ps1"
# Se OK, invocar blindar em mode=maintenance
```

### Opção 3: Manual quando suspeitar drift

Operador invoca: `blindar maintenance`

## O que faz (pipeline reduzido)

| Etapa | Faz |
|---|---|
| 0. Baseline | igual Fase 0 — confirma projeto está ok |
| 1. **Drift detection** | compara `.blindar/state.json` last_updated vs `sec.html` atual. Lista defesas que sumiram |
| 2. **CVE fresh check** | consulta GitHub Advisory + OSV.dev para deps do projeto. Lista CVEs novas crit/high |
| 3. **Stale check** | deps que não receberam bump em >6 meses, base images mutáveis, base de Node/Python/runtime atrás |
| 4. **Re-run preflight** | confirma CI ainda configurada, suite ainda verde |
| 5. **Rounds focados** | só pra drift + CVE detectado, máximo 5 rounds |
| 6. **Mini relatório** | PR `docs(blindar): maintenance report YYYY-Q[1-4]` |

**Sem** discovery completo, **sem** adversarial review pesado, **sem**
production checklist (já passou na release).

## Termination da Fase 7

Para quando:
- CVEs crit/high fechados ou registrados em `.blindar/accept-risk.md`
- Drift detectado tem PR aberto pra fechar
- Máximo de 5 rounds (cap pra não virar Fase 3 disfarçada)

## Atualização do estado

`.blindar/state.json` ganha campo:

```json
{
  "last_maintenance": "2026-09-01T09:00:00Z",
  "maintenance_history": [
    {
      "date": "2026-09-01",
      "drift_found": 2,
      "cves_closed": 1,
      "rounds": 3
    }
  ]
}
```

## Ver também

- [`pipeline/08-drift-detection.md`](08-drift-detection.md) — algoritmo
  específico de drift
- [`agents/patch-management.md`](../agents/patch-management.md) — CVE feed
- [`docs/specs/reproducibility.md`](../docs/specs/reproducibility.md) —
  como garantir que maintenance não regrida

## Limitações honestas

- **Não substitui pentest humano periódico** (vai em
  [`runbooks/pentest-schedule.md`](../runbooks/pentest-schedule.md))
- **Não pega regressão funcional** — assume suite de testes do projeto
  cobre isso
- **Cron fixo (trimestral)** pode ser tarde demais pra CVE crítico
  recém-divulgada. Cap com webhook de CVE feed fica como spec separado.
