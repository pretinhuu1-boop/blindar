# agent: patch-management

Atualização de OS, runtime, libs base. Cobre técnica #5 do baseline.

Complementa [`supply-chain.md`](supply-chain.md): supply-chain cuida da
ingestão (SHA-pin, lockfile, typosquat); este cuida da **rotina de
atualizar** o que já está pinado.

## Quando ativar

1x no ciclo + sempre que CVE crítico em dep direta for detectado.

## Prompt

```
Audit patch posture:
1. Renovate/Dependabot configurado? PRs automáticos de bump?
2. Base image (Docker) fixa em tag mutável (ex: python:3.11) ou pinada?
   Mutável = supply-chain risk.
3. Runtime version: documentada e bump scheduled? (ex: Node 18 → 20).
4. OS packages (se VM/container): unattended-upgrades ou equivalente?
5. CVE feed monitorado? (GitHub Advisory, OSV.dev).
6. SLA de patch para severity: crit ≤24h, high ≤7d, med ≤30d.
7. Dead deps: lib não atualizada em 2+ anos = revisar substituição.

Implement (≤80 LOC + config CI):
1. Renovate/Dependabot config no repo se faltar.
2. Base image pinada por SHA digest, não só tag.
3. CI job que falha em CVE crit/high não acknowledged.
4. docs/patch-policy.md com SLA + processo de emergency patch.
5. sec.html: categoria patch_mgmt:
   - ATK-PM1: deps com CVE crit conhecida (crit)
   - ATK-PM2: base image em tag mutável (high)
   - ATK-PM3: sem auto-bump configurado (med)
```

## Princípios

- **SLA por severidade.** Crit em 24h. Não "quando der".
- **Bump regular > big-bang upgrade.** Renovate pequeno semanal evita
  upgrade de salto de 2 anos.
- **Base image pinada por digest.** `python:3.11@sha256:...`. Tag pura
  é mutável.
- **Acknowledge ≠ ignore.** CVE não fixada precisa decisão registrada
  em `.accept-risk.md` com data de reavaliação.
- **Dead deps são risk.** Lib sem commit em 2+ anos = ATK aberto pra
  substituir/forkar.

## Teste / Verificação

- CI falha em CVE crit/high sem acknowledge
- `docs/patch-policy.md` existe com SLA documentado
- Renovate/Dependabot abriu pelo menos 1 PR no último mês (se não, está
  desconfigurado)

## CVE feed subscription (v0.6.0)

Além de Renovate/Dependabot que reagem a updates, o agente recomenda:

### Subscrição ativa de feeds

| Fonte | Coverage |
|---|---|
| **GitHub Advisory Database** | npm, pip, Maven, NuGet, RubyGems, Composer, Go, Rust |
| **OSV.dev** | meta-feed agregado (Google) — superset do GH Advisory |
| **NVD** (NIST CVE feed) | catálogo formal de CVE |
| **Snyk vuln DB** | comercial, complementa em zero-day |

### Implementação sugerida

GitHub Actions agendado (diário) que:

```yaml
- run: |
    osv-scanner --lockfile=package-lock.json --json > vulns.json
    HIGH=$(jq '[.results[].vulnerabilities[] | select(.severity[].score >= 7)] | length' vulns.json)
    if [ "$HIGH" -gt 0 ]; then
      gh issue create --title "CVE HIGH+ detectada" --body "$(cat vulns.json)"
    fi
```

### Integração com maintenance mode

Fase 7 ([`pipeline/07-maintenance.md`](../pipeline/07-maintenance.md))
roda esse check periodicamente e abre rounds focados em CVEs novas.

### SLA por severity (reforço)

- **crit** (CVSS ≥ 9.0): ≤ 24h pra fix ou acknowledged em accept-risk
- **high** (CVSS 7.0-8.9): ≤ 7d
- **med** (CVSS 4.0-6.9): ≤ 30d
- **low** (CVSS < 4.0): próximo bump regular

## Mapeamento de frameworks

| Framework | Controle |
|---|---|
| ISO 27001 | A.12.6.1 (Management of technical vulnerabilities) |
| NIST CSF | ID.RA, PR.IP-12 |
| CIS Controls | Control 7 (Continuous vulnerability management) |
| PCI-DSS | Req 6.1, Req 6.2 |
| SOC 2 | CC7.1 |
