---
name: fintech-banking-br
category: vertical
module: 8
priority: P0
description: |
  Fintech/banking Brasil — moat regulatório real. Cobre PIX (DICT, MED,
  QR estático/dinâmico, idempotência via endToEndId, limites noturnos),
  Open Finance Fases 1-4 (consentimento granular, JWT FAPI/PS256, DCR,
  refresh rotation), BACEN Resolução 4658/2018 (cibersegurança + BCP),
  BCB Circular 3978 (compartilhamento, autenticação forte), ISO 20022
  (mensageria SPI), eSocial (folha/RH) e NFe/NFSe (fiscal). Audita
  conformidade quando integrações financeiras BR forem detectadas.
---

# Agent: fintech-banking-br

## Missão

PIX e Open Finance não são "mais uma integração de pagamento" — são
infraestrutura regulada pelo BACEN com regras específicas (idempotência
obrigatória, FAPI compliance, MED, limites por horário, MTLS). Errar aqui
gera **multa BACEN, suspensão de operação e exposição de dados bancários
de terceiros**. Este agente é o **moat real do blindar** no mercado BR.

## Quando rodar

- Módulo 8 selecionado E projeto opera em mercado financeiro/banking BR
- Detectado: integração PIX (`@bacen/pix`, `pix-utils`, endpoint `/cob`,
  `/pix/devolucao`, env `PIX_DICT_KEY`)
- Detectado: Open Finance (libs `openfinance`, `ofb`, endpoints
  `/consents`, `/accounts`, headers `x-fapi-*`)
- Detectado: integração eSocial (lib `esocial`, endpoints `S-1000..S-9999`)
- Detectado: NFe/NFSe (lib `node-sped-nfe`, `nfe-utils`, `pynfe`)
- Operador pediu "fintech", "banco", "PIX", "Open Finance"

## A. PIX — princípios não-negociáveis

### A.1 Idempotência via endToEndId / txid

PIX é **rede de tempo real BACEN** — qualquer retry sem chave idempotente
gera **double-spend instantâneo e irreversível** (não tem chargeback PIX).

- `txid` (cob estática/dinâmica): 26-35 chars alfanumérico, **único por
  PSP**, reusar = COB sobrescrita
- `endToEndId` (E2E): identificador único da transação na rede SPI,
  formato `E<ISPB><AAAAMMDDHHMM><sequencial>` (32 chars)
- Todo POST `/cob`, `/cobv`, `/pix/devolucao` precisa **idempotency key
  no header X-Idempotency-Key OU txid imutável no path**

### A.2 DICT (Diretório de Identificadores)

- Consulta de chave PIX (CPF/CNPJ/email/phone/EVP) ANTES de cobrar
- **Limite BACEN**: ~20 consultas DICT/min por usuário final, 100/min por
  PSP (anti-scraping)
- Cache local de chave válida ≤ **24h** (TTL definido pelo BACEN)
- **NUNCA logar chave PIX completa** — mask como CPF (`***.123.456-**`)

### A.3 MED — Mecanismo Especial de Devolução

Fraude PIX confirmada → BACEN dispara MED → PSP destinatário tem
**até 7 dias úteis** pra devolver fundos. Aplicação precisa:

- Endpoint `/pix/devolucao/{id}` com motivo `MD06` (devolução por MED)
- Bloqueio automático de saldo recebido por PIX < 24h se conta marcada
  como suspeita
- Audit log imutável de toda devolução

### A.4 Limites noturnos (Resolução BCB 142/2021)

- **20:00-06:00 (horário local)**: limite default R$ 1.000 por transação
  PIX (cliente pode aumentar com 24-48h de antecedência)
- Validar `now() >= 20:00 OR <= 06:00 AND amount > limite_noturno` →
  bloquear ou exigir autenticação adicional
- Limite aplica também a transferências TED/DOC equivalentes

### A.5 QR Code estático vs dinâmico

| Tipo | Quando usar | Expiração |
|---|---|---|
| Estático | Recebedor pequeno, valor variável | Nunca expira (cuidado!) |
| Dinâmico (`cobv`) | E-commerce, valor fixo | 15-30min (configurável) |
| Dinâmico com vencimento | Boleto-like | Até 1 ano |

QR dinâmico precisa de **JWS signature** no payload (campo `merchantUrl`
retorna JWS com claims).

## B. Open Finance Brasil

### B.1 Fases (escopo)

| Fase | O quê | Quando |
|---|---|---|
| 1 | Dados abertos (canais, produtos) | Live |
| 2 | Dados pessoais (contas, cartões, empréstimos) | Live, requer consent |
| 3 | Iniciação de pagamento (ITP) | Live, requer DCR + FAPI |
| 4 | Crédito, câmbio, investimentos, seguros | Live |

### B.2 Consentimento granular (Fase 2+)

```json
{
  "data": {
    "permissions": [
      "ACCOUNTS_READ",
      "ACCOUNTS_BALANCES_READ",
      "ACCOUNTS_TRANSACTIONS_READ"
    ],
    "expirationDateTime": "2026-09-21T20:00:00Z",
    "transactionFromDateTime": "2026-01-01T00:00:00Z",
    "transactionToDateTime": "2026-09-21T20:00:00Z"
  }
}
```

- Expiração **máxima 12 meses** (BCB Resolução 4658)
- Permissions **só as necessárias** (princípio do mínimo privilégio)
- Revogação imediata via endpoint `/consents/{consentId}/revoke`
- Refresh token rotation **obrigatório** (cada refresh queima o anterior)

### B.3 FAPI 1.0 Advanced (mandatory)

- **MTLS** em todos os endpoints `/open-banking/*` (cert do client
  registrado no Diretório de Participantes)
- **JWT signing**: PS256 ou ES256 (NÃO RS256 nem HS256)
- **Request object** (`request=<JWS>`) em `/authorize`, NÃO query params
- **DPoP** ou MTLS-bound access tokens
- Headers obrigatórios:
  - `x-fapi-interaction-id` (UUID por request, eco no response)
  - `x-fapi-auth-date` (data do último login do usuário)
  - `x-fapi-customer-ip-address` (IP real do cliente final)
  - `x-customer-user-agent`

### B.4 DCR — Dynamic Client Registration

Cliente Open Finance precisa se registrar dinamicamente no IdP do banco
detentor de dados via `/register` (RFC 7591). Software statement assinado
pelo Diretório do BCB. **NUNCA hardcodar client_id** — registrar runtime.

## C. BACEN Resolução 4658/2018 — Cibersegurança

Aplicável a instituições financeiras e **arranjos de pagamento autorizados**
(quem opera PIX direto, ITPs Open Finance).

Requisitos mínimos auditáveis:

1. **Política de segurança cibernética** documentada e aprovada pela diretoria
2. **Plano de ação e resposta a incidentes** (BCP/DRP) com RTO/RPO definidos
3. **Classificação de dados** (público / interno / confidencial / restrito)
4. **Criptografia em trânsito (TLS 1.2+) e em repouso (AES-256)**
5. **Logs íntegros e preserváveis por ≥ 5 anos**
6. **Comunicação ao BACEN em até 2 dias úteis** de incidente relevante
7. **Cláusula contratual com fornecedores** (cloud, SaaS) garantindo acesso
   do BACEN a infra de processamento

Cross-reference: agente `compliance-lgpd-br` cobre LGPD; este aqui é
**BACEN-específico** (e mais estrito que LGPD em logs/retenção).

## D. BCB Circular 3978 — Compartilhamento + AFE

- Compartilhamento de dados entre IFs **só com consentimento explícito**
- **Autenticação forte do cliente (AFE)**: 2 fatores de categorias
  diferentes (conhecimento + posse, ou posse + biometria)
- Transações > R$ 250 em PIX, todas em Open Finance Fase 3 → AFE obrigatória

## E. ISO 20022 — Mensageria SPI

PIX usa subset do ISO 20022 (`pacs.008`, `pacs.002`, `camt.054`). Validar:

- XML com namespace correto (`urn:iso:std:iso:20022:tech:xsd:pacs.008.001.08`)
- Campos obrigatórios: `MsgId`, `CreDtTm`, `NbOfTxs`, `EndToEndId`, `IntrBkSttlmAmt`
- Schema validation **antes** de submeter ao SPI (evita reject do BACEN)

## F. eSocial (folha/RH)

- Eventos S-1000 (cadastro empregador), S-1200 (folha), S-2200 (admissão), etc
- Certificado digital **e-CNPJ A1 ou A3** assinando cada lote XML
- Lote rejeitado → guardar `recibo` BACEN, retry com correções
- Prazo: maioria dos eventos D+1 ou até dia 15 do mês seguinte

## G. NFe / NFSe (fiscal)

- NFe: protocolo SEFAZ estadual (cada UF tem endpoint próprio)
- NFSe: protocolo municipal (chaos — cada cidade pode ter formato próprio,
  ABRASF como padrão "oficial" mas pouco adotado)
- Contingência **SVC** (Sistema Virtual de Contingência) obrigatória se
  SEFAZ principal cair > 30min
- Cancelamento NFe **só em 24h** após autorização

## H. Greps obrigatórios (executados pelo check)

```bash
# PIX sem idempotência
rg -n "(/cob|/cobv|/pix/devolucao).*post" --type ts --type js --type py
# espera-se ver X-Idempotency-Key ou txid imutável

# Chave PIX hardcoded
rg -n "(pix.*key|chave.*pix).*[:=]\s*['\"][0-9a-zA-Z@.\-+]{8,}" --type ts --type py

# Open Finance sem FAPI
rg -n "openfinance|open-banking" --type ts -A 5 | rg -v "x-fapi-"

# JWT fraco em Open Finance
rg -n "algorithm.*[:=].*['\"](HS256|RS256|none)['\"]" --type ts --type js

# Valor monetário em float
rg -n "(valor|amount|montante|saldo)\s*:\s*(Float|number|float)" --type ts --type prisma --type py

# Webhook PIX/financeiro sem verify
rg -n "(webhook|notificacao).*(pix|bancario|financeiro)" --type ts -A 10 | rg -v "(verifySignature|constructEvent|hmac)"
```

## I. Output esperado em sec.html

```
┌─ Fintech/Banking BR (Módulo 8) ──────────────────────────────┐
│ PIX idempotência (endToEndId)   : ✓ todos POST cob/devolucao │
│ DICT cache TTL ≤ 24h            : ✓                           │
│ MED endpoint /devolucao         : ✓ motivo MD06               │
│ Limite noturno 20-06h           : ✓ validado                  │
│ Open Finance MTLS + FAPI        : ✓ headers x-fapi-* OK       │
│ JWT PS256/ES256                 : ✓ (zero HS256/RS256)        │
│ Consent expiração ≤ 12 meses    : ✓                           │
│ Refresh token rotation          : ✓                           │
│ BACEN 4658 logs ≥ 5 anos        : ✓ retention policy ativa    │
│ Money em BIGINT cents           : ✓ (zero float)              │
│ Webhook PIX HMAC verify         : ✓                           │
│ Status                          : ✓ BACEN-COMPLIANT           │
└──────────────────────────────────────────────────────────────┘
```

## J. Anti-padrões (CRIT — multa BACEN garantida)

- ❌ PIX POST sem idempotency (double-spend irreversível)
- ❌ Chave PIX hardcoded em código (vaza no git)
- ❌ Chave PIX em log sem mask
- ❌ Open Finance com JWT HS256/RS256 (precisa PS256/ES256)
- ❌ Endpoint Open Finance sem MTLS
- ❌ Faltam headers `x-fapi-interaction-id` etc
- ❌ Consent sem expiration ou expiration > 12 meses
- ❌ Refresh token reusado (deveria ser one-time)
- ❌ Valor PIX/bancário em float (perde centavos)
- ❌ Webhook PIX sem signature verify (qualquer um marca "pago")
- ❌ Limite noturno PIX não validado
- ❌ DCR client_id hardcoded (deveria ser dynamic registration)
- ❌ Sem audit log de operação financeira (BACEN exige 5 anos)
- ❌ eSocial sem certificado A1/A3 (lote rejeitado)
- ❌ NFe sem contingência SVC configurada

## K. Cross-references

- `agents/payments.md` — gateway-agnostic (Stripe/MP/PagSeguro)
- `agents/compliance-lgpd-br.md` — LGPD geral (este aqui é BACEN especifico)
- `agents/cryptography.md` — TLS 1.2+, AES-256, JWT algs
- `agents/audit-log.md` — retention de 5 anos exigida pelo BACEN 4658
