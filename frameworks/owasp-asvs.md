# OWASP ASVS — Application Security Verification Standard

Padrão **de verificação** mantido pela OWASP. Referência:
**ASVS 5.0** (2024) com 14 capítulos (V1-V14).

Diferente dos outros frameworks aqui (ISO/NIST/CIS) que são tabelas
de controles, **ASVS é uma régua de testes** — para cada item, define
o que precisa ser **verificado por requisição/código/teste**.

> ⚠ É o framework com **maior aderência prática** ao que o blindar
> implementa. Cada agente já cobre vários V's. Esta tabela formaliza
> a relação para gerar coverage report.

## Níveis ASVS

| Nível | Quando aplicar |
|---|---|
| **L1** — opportunistic | App sem dado sensível. Mínimo. |
| **L2** — standard | Maior parte dos apps com dado pessoal/financeiro. **Default blindar**. |
| **L3** — advanced | Saúde, defesa, infraestrutura crítica. |

Discovery (Fase 1) detecta sinais (PII, financeiro, saúde) e seta nível
alvo. Pode ser sobrescrito por `.compliance-target=asvs-L3`.

## V1-V14 ↔ agentes blindar

| ASVS | Capítulo | Agente |
|---|---|---|
| **V1** | Architecture, design, threat modeling | Fase 1 (discovery + threat-model) + [`agents/security.md`](../agents/security.md) |
| **V2** | Authentication | [`agents/access-control.md`](../agents/access-control.md) |
| **V3** | Session management | [`agents/access-control.md`](../agents/access-control.md) |
| **V4** | Access control (autorização) | [`agents/access-control.md`](../agents/access-control.md) |
| **V5** | Validation, sanitization, encoding | [`agents/security.md`](../agents/security.md) (input handling), [`agents/frontend.md`](../agents/frontend.md) (output encoding) |
| **V6** | Stored cryptography | [`agents/cryptography.md`](../agents/cryptography.md) |
| **V7** | Error handling & logging | [`agents/observability.md`](../agents/observability.md) |
| **V8** | Data protection (privacy, retention) | [`agents/compliance.md`](../agents/compliance.md), [`agents/compliance-lgpd-br.md`](../agents/compliance-lgpd-br.md) |
| **V9** | Communications (TLS, certs) | [`agents/cryptography.md`](../agents/cryptography.md), [`agents/network-security.md`](../agents/network-security.md) |
| **V10** | Malicious code / supply chain | [`agents/supply-chain.md`](../agents/supply-chain.md), [`agents/patch-management.md`](../agents/patch-management.md) |
| **V11** | Business logic | [`agents/security.md`](../agents/security.md) (parcial — lógica é específica do app) |
| **V12** | Files and resources (uploads) | [`agents/security.md`](../agents/security.md) |
| **V13** | API & web services (REST, GraphQL) | [`agents/security.md`](../agents/security.md), [`agents/network-security.md`](../agents/network-security.md) |
| **V14** | Configuration | [`agents/devops.md`](../agents/devops.md), [`agents/network-security.md`](../agents/network-security.md) |

## Uso no pipeline

- **Fase 1 (Discovery)**: marca quais V's têm gap. Cada V vira potencial
  ATK no `sec.html`.
- **Fase 3 (Rounds)**: cada round que fecha um requisito ASVS L2/L3
  atualiza coverage.
- **Fase 5 (Production checklist)**: gera relatório `ASVS L2 coverage:
  X/Y requisitos atendidos`.
- **Fase 6 (Relatório final)**: relatório completo de coverage V1-V14.

## Diferencial pra prod

Cada requisito ASVS tem ID estável (ex: `V2.1.1`, `V6.2.3`). Em audit,
você cita "atendemos V2.1.1 pelo controle X com teste Y" — verificável
sem ambiguidade.

## Como usar concretamente

Operador pode pedir ao skill:
```
blindar com target ASVS L2
```

Discovery passa a marcar gap por requisito ASVS específico. Rounds
fecham requisitos. Relatório final lista L2 coverage.

## Limitações

- **V1.3 (arquitetura segura)**: parte é decisão arquitetural humana —
  blindar registra, não decide por você.
- **V11 (lógica de negócio)**: blindar identifica padrões comuns (fraude
  em pagamento, reuso de cupom, race em saldo) mas regra de negócio
  específica precisa do operador documentar.
- Requisitos L3 podem exigir hardware (HSM) ou processo organizacional
  fora de código.

## Fonte

[github.com/OWASP/ASVS](https://github.com/OWASP/ASVS) — projeto oficial,
versionado, em inglês e PT-BR.
