# CIS Controls v8 — mapeamento

Center for Internet Security Controls — conjunto pragmático de 18 controles
priorizados pra ataques comuns. Talvez o mais **acionável** dos frameworks.

## Controles ↔ agentes

| # | Controle CIS | Agente blindar |
|---|---|---|
| 1 | Inventory of enterprise assets | Fase 1 — inventory |
| 2 | Inventory of software assets | [`supply-chain.md`](../agents/supply-chain.md) (lockfile = inventário) |
| 3 | Data protection | [`cryptography.md`](../agents/cryptography.md), [`compliance.md`](../agents/compliance.md) |
| 4 | Secure config of enterprise assets | [`devops.md`](../agents/devops.md), [`network-security.md`](../agents/network-security.md) |
| 5 | Account management | [`access-control.md`](../agents/access-control.md) |
| 6 | Access control management | [`access-control.md`](../agents/access-control.md) |
| 7 | Continuous vulnerability management | [`patch-management.md`](../agents/patch-management.md) |
| 8 | Audit log management | [`observability.md`](../agents/observability.md) |
| 9 | Email & browser protections | ⚠ fora de escopo (endpoint mgmt) |
| 10 | Malware defenses | ⚠ fora de escopo (endpoint AV) |
| 11 | Data recovery | [`backup-recovery.md`](../agents/backup-recovery.md) |
| 12 | Network infrastructure mgmt | [`network-security.md`](../agents/network-security.md) (IaC) |
| 13 | Network monitoring & defense | parcial (logs/audit) + ⚠ infra |
| 14 | Security awareness training | ⚠ fora de escopo (organizacional) |
| 15 | Service provider management | [`supply-chain.md`](../agents/supply-chain.md) |
| 16 | Application software security | [`security.md`](../agents/security.md), [`pentest.md`](../agents/pentest.md), [`frontend.md`](../agents/frontend.md) |
| 17 | Incident response management | runbook `docs/incident-response.md` |
| 18 | Penetration testing | [`pentest.md`](../agents/pentest.md) (DAST/SAST) + recomendação humana |

## Implementation Groups (IGs)

CIS define 3 níveis:
- **IG1** (foundational): subset essencial pra qualquer org
- **IG2** (focused): orgs com pessoal técnico dedicado
- **IG3** (enterprise): orgs com programa de seg maduro

O blindar cobre **IG1 + boa parte de IG2** automaticamente. IG3 exige
processos organizacionais fora de código.

## Output

Com flag `target=cis`, Fase 6 reporta coverage por controle:
```
CIS Controls v8 coverage: 15/18 controles com agente ativo
Fora de escopo: #9, #10, #14 (endpoint AV, browser, training)
```
