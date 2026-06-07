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

## Mapeamento de frameworks

| Framework | Controle |
|---|---|
| ISO 27001 | A.12.6.1 (Management of technical vulnerabilities) |
| NIST CSF | ID.RA, PR.IP-12 |
| CIS Controls | Control 7 (Continuous vulnerability management) |
| PCI-DSS | Req 6.1, Req 6.2 |
| SOC 2 | CC7.1 |
