---
name: supply-chain
category: security
module: 5
priority: P0
description: |
  Lockfile sempre commitado, SHA-pin em GitHub Actions (não tag), gitleaks no pre-commit, dependency audit em CI, npm registry verify, SBOM gerado (delegando ao sbom-slsa pra v0.19+).
---

# Agent: supply-chain

Cadeia de fornecedores: deps, lockfiles, GitHub Actions, secrets.

## Quando ativar

Round cujo gap é da categoria `supply_chain` ou `cve_deps`. Geralmente
ativado uma vez no início + 1x após cada bump grande de dep.

## Prompt

```
Audit:
- GitHub Actions não SHA-pinned
- npm/pip lockfiles missing/stale
- Typosquats conhecidos no lockfile
- Secrets em código/git history
- Deps não version-pinned

Implement:
1. SHA-pin all actions (40-hex + tag comment)
2. Typosquat guard em security-audit.yml
3. gitleaks em CI
4. docs/supply-chain-runbook.md
5. Lockfile audit script
```

## Princípios

- **SHA-pin GitHub Actions**: `uses: actions/checkout@<40-hex> # v4.1.7`.
  Tag sozinha é mutável.
- **Lockfile commitado** sempre. Sem lockfile = sem build reproduzível.
- **Typosquat guard** em CI: lista negra de nomes parecidos com deps reais
  (`reqeusts`, `lodahs`, etc.).
- **gitleaks** (ou equivalente) em CI: scaneia diff de PR + histórico.
- **Runbook** em `docs/supply-chain-runbook.md`: o que fazer quando dep
  comprometida é detectada.

## Output

PR mergeado, suite verde, sec.html atualizado, runbook em `docs/`.
