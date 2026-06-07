# PCI-DSS v4.0 — mapeamento

Padrão obrigatório para quem **processa, transmite ou armazena dados de
cartão**. Se o projeto não toca cartão, este framework **não se aplica**.

## ⚠ Ativação condicional

Discovery (Fase 1) ativa este framework SÓ se detectar:
- Integração com gateway de pagamento (Stripe, PagSeguro, Mercado Pago,
  Cielo, Rede, etc.)
- Campos no schema/UI: `card_number`, `cardholder`, `cvv`, `pan`
- Bibliotecas: `stripe`, `mercadopago`, etc.

Mesmo com integração, **o ideal é NUNCA tocar PAN** — usar tokenização
do provider. Se PAN passa pelo seu sistema, escopo PCI-DSS explode.

## 12 Requirements

| # | Requirement | Agente |
|---|---|---|
| 1 | Network security controls | [`network-security.md`](../agents/network-security.md) |
| 2 | Secure configurations | [`devops.md`](../agents/devops.md) |
| 3 | Protect stored account data | [`cryptography.md`](../agents/cryptography.md) |
| 4 | Protect data in transmission | [`cryptography.md`](../agents/cryptography.md) |
| 5 | Protect against malware | ⚠ fora de escopo (endpoint) |
| 6 | Develop secure systems | [`security.md`](../agents/security.md), [`pentest.md`](../agents/pentest.md), [`patch-management.md`](../agents/patch-management.md) |
| 7 | Restrict access (need-to-know) | [`access-control.md`](../agents/access-control.md) |
| 8 | Identify users + auth | [`access-control.md`](../agents/access-control.md) (MFA obrigatório PCI) |
| 9 | Restrict physical access | ⚠ fora de escopo |
| 10 | Log & monitor | [`observability.md`](../agents/observability.md) |
| 11 | Test security regularly | [`pentest.md`](../agents/pentest.md) |
| 12 | Information security policy | ⚠ runbook (organizacional) |

## Gates específicos do agente compliance-pci

Se ativado, gates extras na Fase 5:

- [ ] PAN nunca aparece em log (grep estático de 16-19 dígitos sequenciais)
- [ ] CVV NUNCA armazenado (grep no schema falha em campo `cvv`)
- [ ] Tokenização do provider em uso (não PAN raw na DB)
- [ ] MFA obrigatório para qualquer admin que toca dados de cartão
- [ ] TLS 1.2+ enforced em endpoints de pagamento
- [ ] Pentest agendado por release maior (registrado em runbook)

## Recomendação principal

**Use SAQ-A ou SAQ-A-EP do provider.** O escopo regulatório encolhe
drasticamente quando o PAN nunca entra no seu sistema. Stripe Elements,
Mercado Pago Bricks, etc. existem exatamente pra isso.

Se você TEM que armazenar PAN, o blindar consegue ajudar com o lado
técnico, mas a certificação PCI exige auditor formal — fora do escopo
de skill.
