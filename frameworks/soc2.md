# SOC 2 — mapeamento

Muito usado por SaaS / cloud / B2B. Avalia 5 **Trust Service Criteria**.

## TSC ↔ agentes

| TSC | Foco | Agentes |
|---|---|---|
| **Security** (CC) | Comum a todos — proteção contra acesso não-autorizado | TODOS os agentes de segurança |
| **Availability** (A) | Sistema disponível conforme contratado | [`resilience.md`](../agents/resilience.md), [`backup-recovery.md`](../agents/backup-recovery.md) |
| **Processing Integrity** (PI) | Processamento completo, válido, autorizado | [`security.md`](../agents/security.md) (validação), [`observability.md`](../agents/observability.md) |
| **Confidentiality** (C) | Info confidencial protegida | [`cryptography.md`](../agents/cryptography.md), [`access-control.md`](../agents/access-control.md) |
| **Privacy** (P) | PII tratado conforme política | [`compliance.md`](../agents/compliance.md), [`compliance-lgpd-br.md`](../agents/compliance-lgpd-br.md) |

## Common Criteria (CC) — sempre obrigatório

| CC série | Foco | Agente |
|---|---|---|
| CC1 | Control environment | ⚠ organizacional |
| CC2 | Communication & information | parcial (runbook) |
| CC3 | Risk assessment | Fase 1 + `.accept-risk.md` |
| CC4 | Monitoring | [`observability.md`](../agents/observability.md), [`pentest.md`](../agents/pentest.md) |
| CC5 | Control activities | git + PR + CI obrigatórios |
| CC6 | Logical & physical access | [`access-control.md`](../agents/access-control.md), [`network-security.md`](../agents/network-security.md) |
| CC7 | System operations | [`observability.md`](../agents/observability.md), [`patch-management.md`](../agents/patch-management.md) |
| CC8 | Change management | git workflow + CI verde antes de merge |
| CC9 | Risk mitigation | [`security.md`](../agents/security.md), runbooks |

## Type I vs Type II

- **Type I**: snapshot de controles em uma data
- **Type II**: controles **operando** durante 6-12 meses

Blindar ajuda no **desenho** dos controles (Type I) e no **registro
contínuo** via audit log + sec.html versionado (suporta Type II), mas a
auditoria formal exige firma de auditoria.

## Output

Com flag `target=soc2`, relatório Fase 6 mostra:
```
SOC 2 coverage:
  Security (CC1-CC9): técnico forte; CC1/CC2 dependem de organização
  Availability: forte (resilience + backup)
  Confidentiality: forte (crypto + access)
  Privacy: forte se LGPD-BR ativo
  Processing Integrity: médio (validação técnica OK, processo organizacional fora)
```
