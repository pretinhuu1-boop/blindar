# COBIT 2019 — mapeamento (stub)

> ⚠ **Cobertura baixa.** COBIT é framework de **governança de TI corporativa**.
> A maior parte dos seus controles é **organizacional** (papéis, processos
> de decisão, indicadores estratégicos), não técnica. O blindar — que mexe
> em código — cobre uma fatia pequena.

## Domínios COBIT (5)

| Domínio | Sigla | Foco | Cobertura blindar |
|---|---|---|---|
| Evaluate, Direct, Monitor | EDM | Governança | ⚠ organizacional |
| Align, Plan, Organise | APO | Estratégia, arquitetura, risco | parcial (APO13 — gestão de segurança) |
| Build, Acquire, Implement | BAI | Mudança, projeto, requisitos | parcial (BAI03, BAI10) |
| Deliver, Service, Support | DSS | Operação, incidentes, continuidade | parcial (DSS04, DSS05, DSS06) |
| Monitor, Evaluate, Assess | MEA | Conformidade, auditoria | parcial (MEA02, MEA03) |

## Objetivos com cobertura técnica

| COBIT | Tema | Agente |
|---|---|---|
| APO13 | Managed security | TODOS os agentes de segurança |
| BAI10 | Managed configuration | [`devops.md`](../agents/devops.md) |
| DSS04 | Managed continuity | [`backup-recovery.md`](../agents/backup-recovery.md), [`resilience.md`](../agents/resilience.md) |
| DSS05 | Managed security services | [`security.md`](../agents/security.md), [`network-security.md`](../agents/network-security.md), [`pentest.md`](../agents/pentest.md) |
| DSS06 | Managed business process controls | [`compliance.md`](../agents/compliance.md), [`observability.md`](../agents/observability.md) |
| MEA02 | Managed system of internal control | git + CI + audit chain (parcial) |

## Recomendação

Se sua org persegue COBIT, use o blindar para a **camada técnica** dos
objetivos acima e **complemente com processo organizacional**: comitê de
TI, indicadores estratégicos, RACI de decisão. Isso não vai pra código.

## Output

Não é gerado relatório COBIT específico — sobreposição com ISO 27001 +
NIST CSF cobre a parte técnica. Se necessário, use o relatório desses
dois e mapeie manualmente pra COBIT.
