# NIST Cybersecurity Framework (CSF) — mapeamento

Framework do NIST muito usado globalmente como guia operacional. Versão de
referência: **CSF 2.0** (2024) — 6 funções.

## Funções

| Função | Sigla | Foco | Cobertura blindar |
|---|---|---|---|
| **Govern** | GV | Governança, papéis, estratégia | parcial (políticas em runbook) |
| **Identify** | ID | Ativos, riscos, fornecedores | discovery (Fase 1) |
| **Protect** | PR | Acesso, treinamento, dados, infra | **alta** |
| **Detect** | DE | Monitoramento, eventos, análise | observability + audit |
| **Respond** | RS | Resposta a incidente, mitigação | runbook |
| **Recover** | RC | Restauração, comunicação | backup-recovery + runbook |

## Mapeamento de categorias ↔ agentes blindar

### GV — Govern

| Categoria | Controle | Agente |
|---|---|---|
| GV.OC | Organizational context | ⚠ runbook |
| GV.RM | Risk management strategy | `.accept-risk.md` (parcial) |
| GV.SC | Cybersecurity supply chain | [`supply-chain.md`](../agents/supply-chain.md) |

### ID — Identify

| Categoria | Controle | Agente |
|---|---|---|
| ID.AM | Asset management | Fase 1 — inventory |
| ID.RA | Risk assessment | Fase 1 — threat-model |

### PR — Protect (maior cobertura)

| Categoria | Controle | Agente |
|---|---|---|
| PR.AA | Authentication & access | [`access-control.md`](../agents/access-control.md) |
| PR.AT | Awareness & training | ⚠ fora de escopo (organizacional) |
| PR.DS | Data security | [`cryptography.md`](../agents/cryptography.md), [`compliance.md`](../agents/compliance.md) |
| PR.IR | Infrastructure resilience | [`resilience.md`](../agents/resilience.md), [`backup-recovery.md`](../agents/backup-recovery.md) |
| PR.PS | Platform security | [`patch-management.md`](../agents/patch-management.md), [`devops.md`](../agents/devops.md) |

### DE — Detect

| Categoria | Controle | Agente |
|---|---|---|
| DE.CM | Continuous monitoring | [`observability.md`](../agents/observability.md) |
| DE.AE | Adverse event analysis | [`observability.md`](../agents/observability.md) + audit chain |

### RS — Respond

| Categoria | Controle | Agente |
|---|---|---|
| RS.MA | Management | runbook `docs/incident-response.md` |
| RS.AN | Analysis | logs estruturados (observability) |
| RS.CO | Communications | runbook |
| RS.MI | Mitigation | [`security.md`](../agents/security.md) — fix de ATK |

### RC — Recover

| Categoria | Controle | Agente |
|---|---|---|
| RC.RP | Recovery planning | [`backup-recovery.md`](../agents/backup-recovery.md) |
| RC.CO | Communications | runbook |

## Família NIST SP 800 (referência)

Além do CSF, NIST mantém a família **SP 800** com padrões mais detalhados.
Não criamos arquivo separado pra cada — sobrepõem CSF + agents existentes:

| Publicação | Foco | Onde no blindar |
|---|---|---|
| **SP 800-53** | Catálogo de controles de segurança e privacidade | Mapeia 1-1 com agents (similar a ISO 27001 A.8). Use [`iso-27001.md`](iso-27001.md) como proxy. |
| **SP 800-61** | Computer Security Incident Handling Guide | [`runbooks/`](../runbooks/) + runbook gerado `docs/incident-response.md` |
| **SP 800-115** | Technical Guide to Information Security Testing | [`agents/pentest.md`](../agents/pentest.md) seção metodologias |
| **SP 800-37** | Risk Management Framework (RMF) | `.accept-risk.md` + Fase 1 (threat-model) + Fase 5 (production gates) |
| **SP 800-63** | Digital identity guidelines (auth) | [`agents/access-control.md`](../agents/access-control.md) |
| **SP 800-88** | Media sanitization | [`agents/compliance.md`](../agents/compliance.md) (data deletion) |

Para auditoria FedRAMP/governamental dos EUA, SP 800-53 é o catálogo de
referência. O blindar **não certifica FedRAMP** — fornece controles
técnicos que servem como evidência.

## Output esperado

Com flag `target=nist-csf`, relatório Fase 6 mostra coverage por função:

```
NIST CSF 2.0 coverage:
  GV: parcial (1/3 categorias)
  ID: forte (2/2)
  PR: forte (4/5 — PR.AT fora de escopo)
  DE: forte (2/2)
  RS: médio (técnico OK, comunicação fica organizacional)
  RC: forte (1/2 + runbook)
```
