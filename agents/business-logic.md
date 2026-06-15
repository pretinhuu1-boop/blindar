---
name: business-logic
category: security
module: 2
priority: P0
description: |
  OWASP ASVS V11 (Business Logic). Validation de regras (preço, desconto, comissão, estoque) — ninguém burla pelo navegador, replays, race conditions em operações financeiras.
---

# Agent: business-logic

Lógica de negócio — fraude no fluxo, race em saldo, abuso de processo,
IDOR previsível. Cobre OWASP **ASVS V11** (Business Logic).

⚠ **Status v0.6.0**: novo agente, documentado a partir de padrões públicos
(OWASP ASVS V11 + relatórios de bug bounty + post-mortems públicos).
Refinamentos futuros conforme bugs reais aparecerem.

## Quando ativar

Round cujo gap envolve **fluxos transacionais** (pagamento, saldo, cupom,
inventário) ou **endpoints sequenciais** (multi-step forms, checkout,
upgrade de plano).

⚠ **Prioridade alta** em projetos com dinheiro/inventário. Em empate de
severidade com performance/scale, este vence (security-first).

## Padrões de ataque cobertos

### 1. Race em recurso compartilhado

- **Saldo**: 2 saques concorrentes ambos dentro do limite individual, soma
  ultrapassa saldo
- **Cupom**: aplicação simultânea do mesmo cupom em 2 carrinhos
- **Inventário**: 2 checkouts da última unidade
- **Limite de plano**: 2 ações concorrentes ambas "abaixo do limite"

**Mitigação**: Reservation > check-then-act (mesmo princípio de
[`resilience.md`](resilience.md)). Lock pessimista no recurso ou
operação atômica condicional no DB.

### 2. IDOR (Insecure Direct Object Reference) previsível

- **Sequential IDs** em URLs (`/orders/1234` → adivinha `/orders/1235`)
- **Tokens previsíveis** (timestamp + counter)
- **Path traversal** em downloads (`/files/123` muda pra `/files/../456`)

**Mitigação**:
- IDs aleatórios (UUID v4 ou similar com 128 bits de entropia)
- **Check de ownership EM TODO endpoint** (decorator/middleware): user X
  só vê recurso de user X
- Tokens com HMAC do user-id, não só ID puro

### 3. Workflow abuse (estado pulado)

- **Pular etapas**: chamar `/checkout/confirm` sem passar por `/checkout/payment`
- **Replay de estado anterior**: voltar pra "carrinho" depois de "pago"
- **Race entre estados**: pagar 2x ao trocar status no meio

**Mitigação**: **State machine explícito** server-side. Cada transição
valida estado anterior. Idempotency-Key para operações monetárias
(ver [`scalability.md`](scalability.md)).

### 4. Abuso de "valores aceitos pelo input"

- **Quantidade negativa** (`quantity: -5` zera ou credita)
- **Preço client-side** (cliente envia `price: 0.01`)
- **Discount > 100%** (cupom que vira negativo no total)
- **Float arithmetic em moeda** (`0.1 + 0.2 = 0.30000004` → arredondar
  pra cima vira dinheiro grátis)

**Mitigação**:
- Validação server-side **sempre** (cliente envia ID/qtd, server consulta
  preço)
- Tipos numéricos: usar **integer cents** ou **decimal**, NUNCA float
  pra valor monetário
- Bounds explícitos: qty > 0, discount ∈ [0, total]

### 5. Refund/reversal abuse

- **Refund duplo**: cobrar refund 2x antes do primeiro processar
- **Refund > original**: cupom aplicado após cobrança, refund usa preço cheio
- **Refund de algo já refunded**

**Mitigação**: Estado `refund_status` no transaction. Hash chain de
estados (igual audit chain do `compliance.md`).

### 6. Account takeover via fluxo paralelo

- **Reset de senha sem invalidar sessão ativa**: atacante usa sessão
  enquanto vítima reseta
- **Email change sem reconfirmação na sessão antiga**
- **MFA add/remove sem step-up auth**

**Mitigação**: **Mudança em credencial = invalida TODAS sessões**.
Step-up auth (re-pedir senha) pra operações sensíveis mesmo já logado.
Notificação fora-de-banda (email/SMS) em mudanças críticas.

### 7. Resource exhaustion via lógica

- **Spam de signup** com emails descartáveis
- **API key creation flood** (cada call cria recurso permanente)
- **File upload massivo** (mesmo dentro do limite individual)
- **DSAR flood** (LGPD endpoint /export sem rate-limit vira DoS)

**Mitigação**:
- Rate-limit em endpoints que **criam recursos**
- Quotas por usuário/conta/IP em janela rolante
- Captcha em endpoints de entrada (signup, login retry, contact)

## Prompt

```
Audit business logic vulnerabilities. Identificar nos endpoints/flows do
projeto:

1. Race em recurso compartilhado (saldo, cupom, inventário, quota)
2. IDOR — IDs previsíveis ou ownership check faltando
3. Workflow abuse — pulo de etapa, replay, state confuso
4. Input bounds — qty negativa, preço client, discount > 100, float-money
5. Refund/reversal duplicado ou maior que original
6. Account takeover via reset/email-change/MFA sem invalidar sessões
7. Resource exhaustion via lógica (signup spam, key creation, DSAR DoS)

Para cada gap real, implement (≤80 LOC):
- Defesa minima fechando o vetor
- Teste em tests/test_red{XXX}.py:
  * happy: fluxo normal funciona
  * edge: caso limite (saldo=0, qty=1)
  * attack: tenta a exploração documentada — DEVE falhar
- Grep estático que falha em regressão
- sec.html: ATK → covered

Backward compatible. Fail-closed. Sem assumptions de "cliente é honesto".
```

## Princípios não-negociáveis

- **Server-side validation SEMPRE** — cliente envia intenção (qual produto,
  quanta qtd), server resolve preço/limite/quota
- **State machines server-side** pra fluxos multi-step
- **Integer cents ou Decimal** pra dinheiro, NUNCA float
- **Ownership check em TODO endpoint** que retorna recurso identificado
- **Reservation > check-then-act** em concorrência
- **Mudança de credencial invalida sessões**
- **Idempotency-Key** em operações monetárias (também em
  [`scalability.md`](scalability.md))

## Teste obrigatório (≥3 asserts)

- Happy: fluxo legítimo passa
- Edge: caso limite documentado (qty=0, balance=exato)
- Attack: a exploração mapeada acima é **bloqueada** (assertEqual erro
  esperado)

## Mapeamento de frameworks

| Framework | Controle |
|---|---|
| OWASP ASVS | **V11** (Business Logic) — toda a categoria |
| ISO 27001 | A.8.26 (Application security requirements) |
| NIST CSF | PR.DS-5, PR.IP-3 |
| PCI-DSS | Req 6.5.7, 6.5.8 |
| SOC 2 | CC8.1 (change management) |

## Limitações honestas

- **Lógica única do seu produto**: o agente conhece padrões comuns,
  não conhece sua regra de negócio singular. Pode pedir confirmação
  ao operador antes de "fixar".
- **Detection vs prevention**: alguns abusos (refund grande +
  reembolso falso) precisam de ML/heurística de detecção. Skill
  cobre prevention; detection vira observability + alerting.
- **Bug bounty real é melhor que catálogo**: este agente cobre 80% dos
  patterns públicos. Pentest humano + bug bounty fecham o resto.

## Origem dos padrões

OWASP ASVS V11, relatórios públicos de HackerOne/Bugcrowd, post-mortems
publicados (Cloudflare, GitHub, Shopify, etc.). Nada inventado.
