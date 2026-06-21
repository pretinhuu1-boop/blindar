---
name: payments
category: payments
module: 4
priority: P0
description: |
  Receber dinheiro sem perder dinheiro nem cobrar duas vezes. Cobre:
  idempotency keys obrigatórias, webhook HMAC + replay protection +
  dedup, refund/chargeback flow auditado, status machine completa,
  reconciliação diária, fraud detection básico, PCI-DSS awareness
  (NUNCA tocar PAN), Strong Customer Authentication, suporte a
  Stripe/Mercado Pago/PagSeguro/PIX.
---

# Agent: payments

## Missão

Bug em pagamento = perda direta de dinheiro + cliente bravo + chargeback +
problema legal. Este agente garante que **toda transação é idempotente,
auditável e reconciliável**.

## Quando rodar

- Módulo 4 selecionado E projeto cobra dinheiro
- Detectado: `stripe` / `mercadopago` / `pagseguro` / `pix` / `paypal` em
  `package.json` ou imports
- Operador pediu "pagamento", "cobrança", "checkout"

## A. Princípios não-negociáveis

1. **NUNCA processar cartão diretamente** — sempre via gateway tokenizado
2. **NUNCA armazenar PAN/CVV/track data** (PCI-DSS Level 1 sem necessidade)
3. **NUNCA aceitar `amount` do cliente sem validar** (BE busca preço no DB)
4. **NUNCA usar `float`/`decimal` pra valor** (BIGINT cents — db-architect)
5. **SEMPRE idempotency key** em endpoint que cria payment
6. **SEMPRE webhook HMAC verify** antes de processar
7. **SEMPRE audit log** de cada estado de transação

## B. Status machine completa

```
created → pending → processing → paid → fulfilled
                          ↓        ↓
                      failed   refunded
                          ↓        ↓
                      retrying  chargeback
                                   ↓
                                disputed
```

```sql
CREATE TYPE payment_status AS ENUM (
  'created','pending','processing','paid','failed','retrying',
  'fulfilled','refunded','partially_refunded','chargeback','disputed','cancelled'
);

CREATE TABLE payments (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid_v7(),
  tenant_id       UUID NOT NULL,
  user_id         UUID NOT NULL,
  order_id        UUID,
  amount_cents    BIGINT NOT NULL CHECK (amount_cents > 0),
  currency        CHAR(3) NOT NULL,
  gateway         TEXT NOT NULL,              -- stripe|mercadopago|pagseguro|pix
  gateway_id      TEXT,                       -- ID do gateway (pi_xxx, etc.)
  status          payment_status NOT NULL DEFAULT 'created',
  status_reason   TEXT,
  idempotency_key TEXT UNIQUE NOT NULL,
  method          TEXT,                       -- card|pix|boleto|...
  meta            JSONB,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  paid_at         TIMESTAMPTZ,
  refunded_at     TIMESTAMPTZ,
  version         INTEGER NOT NULL DEFAULT 1
);

CREATE INDEX idx_payments_tenant_status ON payments(tenant_id, status, created_at DESC);
CREATE INDEX idx_payments_gateway_id ON payments(gateway, gateway_id);
```

### Histórico imutável de transições

```sql
CREATE TABLE payment_events (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid_v7(),
  payment_id   UUID NOT NULL REFERENCES payments(id),
  event_type   TEXT NOT NULL,                 -- 'status_changed', 'refund', 'webhook_received'
  from_status  payment_status,
  to_status    payment_status,
  amount_cents BIGINT,
  source       TEXT NOT NULL,                 -- 'api', 'webhook', 'admin', 'reconciliation'
  actor_id     UUID,
  gateway_payload JSONB,                      -- payload bruto do gateway (audit)
  at           TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

## C. Idempotency obrigatória

```ts
@Post('payments')
async create(@Body() dto: CreatePaymentDto, @Headers('idempotency-key') key: string) {
  if (!key) throw new BadRequest('Idempotency-Key header obrigatório');
  if (key.length < 16 || key.length > 128) throw new BadRequest('key inválida');

  // Tenta retornar existente
  const existing = await db.payment.findUnique({ where: { idempotency_key: key } });
  if (existing) {
    // Mesmo payload? retorna cached. Diverge? 422
    if (hashPayload(dto) !== hashPayload(existing.original_payload)) {
      throw new UnprocessableEntity('idempotency_key conflict');
    }
    return existing;
  }

  // Validar preço NO BACKEND (não confiar no cliente)
  const order = await db.order.findUnique({ where: { id: dto.order_id, tenant_id } });
  if (order.amount_cents !== dto.amount_cents) throw new BadRequest('amount_mismatch');

  // Criar payment intent no gateway
  const gw = await stripe.paymentIntents.create({
    amount: order.amount_cents,
    currency: order.currency,
    metadata: { paymentId, tenantId },
    statement_descriptor: 'SALONPRO',           // descrição na fatura do cliente
  }, { idempotencyKey: key });                  // Stripe também usa o mesmo key

  return await db.payment.create({ /* ... */ });
}
```

## D. Webhook (entrada) — receita à prova de bala

```ts
@Post('webhooks/stripe')
async handleStripe(@Req() req: RawRequest) {
  // 1. Verificar signature (HMAC)
  const sig = req.headers['stripe-signature'];
  let event: Stripe.Event;
  try {
    event = stripe.webhooks.constructEvent(req.rawBody, sig, process.env.STRIPE_WEBHOOK_SECRET);
  } catch (err) {
    throw new BadRequest('invalid_signature');
  }

  // 2. Anti-replay (já processou esse evento?)
  const seen = await db.webhookEvent.findUnique({ where: { event_id: event.id } });
  if (seen) return { received: true, cached: true };

  // 3. Salvar evento ANTES de processar (caso processamento falhe)
  await db.webhookEvent.create({
    data: { event_id: event.id, type: event.type, payload: event, status: 'pending' }
  });

  // 4. Retornar 200 RÁPIDO, processar async
  setImmediate(() => processWebhookAsync(event.id));
  return { received: true };
}

async function processWebhookAsync(eventId: string) {
  const event = await db.webhookEvent.findUnique({ where: { event_id: eventId } });
  try {
    // Idempotente — pode rodar 2x sem efeito colateral
    await applyEventToPayment(event.payload);
    await db.webhookEvent.update({
      where: { event_id: eventId }, data: { status: 'processed', processed_at: new Date() }
    });
  } catch (err) {
    await db.webhookEvent.update({
      where: { event_id: eventId }, data: { status: 'failed', error: err.message }
    });
    // Stripe vai retentar automaticamente
    throw err;
  }
}
```

### Regras

- **Retornar 200 < 5s** — senão Stripe/MP marca como falha e retenta
- Processamento real **assíncrono** (fila)
- **DLQ** se falhar 5x — alerta humano
- Webhook secret **rotacionado a cada 90 dias**

## E. Refund flow auditado

```ts
@Post('admin/payments/:id/refund')
@Roles('ADMIN','MASTER')
async refund(@Param('id') paymentId, @Body() { amount_cents, reason }, @Req() req) {
  // Validações
  if (!reason || reason.length < 10) throw new BadRequest('motivo obrigatório, ≥10 chars');

  const payment = await db.payment.findUnique({ where: { id: paymentId } });
  if (payment.status !== 'paid' && payment.status !== 'partially_refunded') {
    throw new Conflict('only paid payments can be refunded');
  }

  const alreadyRefunded = payment.refunded_cents || 0;
  if (alreadyRefunded + amount_cents > payment.amount_cents) {
    throw new BadRequest('would exceed original amount');
  }

  // Chama gateway COM idempotency
  const refundKey = `refund-${paymentId}-${Date.now()}`;
  const refund = await stripe.refunds.create({
    payment_intent: payment.gateway_id, amount: amount_cents
  }, { idempotencyKey: refundKey });

  // Audit + status update
  await db.$transaction([
    db.payment.update({
      where: { id: paymentId, version: payment.version },
      data: {
        refunded_cents: { increment: amount_cents },
        status: alreadyRefunded + amount_cents === payment.amount_cents ? 'refunded' : 'partially_refunded',
        version: { increment: 1 }
      }
    }),
    db.paymentEvent.create({
      data: { payment_id: paymentId, event_type: 'refund', amount_cents,
              source: 'admin', actor_id: req.user.id, gateway_payload: refund }
    }),
    db.auditLog.create({ data: { /* type: 'refund', reason, ... */ } })
  ]);

  // Notifica cliente
  await email.send(payment.user_id, 'refund_processed', { amount_cents });
}
```

## F. Reconciliação diária (cron)

```ts
@Cron('0 3 * * *')   // 3am todo dia
async reconcile() {
  // Pega 24h do gateway
  const gwTransactions = await stripe.balanceTransactions.list({
    created: { gte: yesterday(), lt: today() }
  });

  for (const tx of gwTransactions.data) {
    const local = await db.payment.findFirst({ where: { gateway_id: tx.source } });

    if (!local) {
      // Gateway tem, banco não → ALERTA (webhook perdido?)
      await alert.critical('payment_missing_in_db', { tx_id: tx.id });
    } else if (local.amount_cents !== Math.abs(tx.amount)) {
      // Valor diverge → ALERTA
      await alert.critical('payment_amount_mismatch', { local, gateway: tx });
    } else if (local.status === 'created' && tx.status === 'available') {
      // Banco diz "criado", gateway diz "disponível" → conciliar
      await applyEventToPayment({ type: 'payment.succeeded', data: tx });
    }
  }

  // Verso: banco diz "paid", gateway não tem → fraud? bug?
  const pendingLocal = await db.payment.findMany({
    where: { status: 'paid', created_at: { gte: yesterday() } }
  });
  for (const p of pendingLocal) {
    if (!gwTransactions.data.find(t => t.source === p.gateway_id)) {
      await alert.warning('local_paid_no_gateway_match', { paymentId: p.id });
    }
  }
}
```

## G. Fraud detection básico

- **Velocity check**: > 5 tentativas/15min mesmo IP/email → CAPTCHA
- **Geo mismatch**: IP em país X, bandeira do cartão em Y → step-up (3DS)
- **Amount threshold**: tx > média histórica do user × 5 → confirma email
- **AVS / CVV mismatch** (Stripe Radar / MP Antifraud): bloquear high-risk
- **Blacklist** de email/CPF/IP comprometido (alimentada por chargebacks)

## H. PCI-DSS awareness

- **NUNCA** PAN/CVV/track no log, banco, request, response, screenshot
- Cliente envia diretamente ao gateway (Stripe Elements, MercadoPago Bricks)
- Backend só recebe **token** ou **payment_method_id**
- Compliance level: **SAQ A** (não toca dados de cartão) é o alvo

## I. SCA / 3DS (Strong Customer Authentication — Europa, e crescente)

```ts
const intent = await stripe.paymentIntents.create({
  amount, currency,
  payment_method_types: ['card'],
  setup_future_usage: 'off_session',          // pra cobrar depois sem 3DS
  // Stripe escolhe automatic 3DS quando exigido (Europa, alguns BR)
});
// Cliente confirma no front com stripe.confirmCardPayment (pode abrir 3DS)
```

## J. PIX (Brasil específico)

- **QR code dinâmico** com expiração (15-30min)
- Webhook quando pago — geralmente < 30s
- Validar CPF/CNPJ do pagador bate com cadastro (anti-lavagem)
- DICT lookup pra validar chave PIX antes de pagar
- Devolução PIX → endpoint `/pix/devolucao` do BACEN

## K. Greps obrigatórios

```bash
# Valor em float (ERRADO)
rg -n "amount[:\s]*\d+\.\d+" --type ts --type py
rg -n "price[:\s]*number" --type ts

# Salvar dado de cartão (CRIT — PCI violation)
rg -ni "(pan|card_number|cvv|cvc|security_code).*[:=]" --type ts --type py
rg -n "process\.env\..*CARD_" --type ts

# Webhook sem signature verify (CRIT)
rg -n "webhook.*\.json\(\)" --type ts -B 5 | rg -v "(constructEvent|verifySignature|verifyHmac)"

# Endpoint payment sem idempotency
rg -n "@Post.*payment" --type ts -A 10 | rg -v "idempotency"
```

## Output esperado em sec.html

```
┌─ Payments (Módulo 4) ────────────────────────────────────┐
│ Idempotency em POST payments  : ✅ obrigatório            │
│ Webhook HMAC verify           : ✅ Stripe constructEvent  │
│ Webhook dedup (event_id)      : ✅                         │
│ Webhook async + DLQ           : ✅                         │
│ Status machine completa       : ✅ 12 estados             │
│ Histórico imutável de eventos : ✅ payment_events         │
│ Refund auditado + motivo      : ✅                         │
│ Reconciliação diária          : ✅ cron 3am               │
│ Fraud: velocity/geo/amount    : ✅                         │
│ Zero PAN/CVV no banco         : ✅ (greps clean)          │
│ Valor sempre BIGINT cents     : ✅ (sem float)            │
│ 3DS / SCA suportado           : ✅                         │
│ Status                        : ✅ MONEY-SAFE             │
└───────────────────────────────────────────────────────────┘
```

## Intelligence (⭐ v0.21) — profile por gateway

Stripe, Mercado Pago, PagSeguro e PIX têm contratos diferentes. Lê
`.blindar/intelligence.yml`:

```yaml
payments:
  active_gateways:
    # Quais estão em uso (detect: imports do client + env vars)
    - stripe
    - mercadopago
    - pagseguro
    - pix_direct                       # PSP direto BACEN

  gateway_profiles:
    stripe:
      webhook_signature_header: "stripe-signature"
      webhook_signature_lib: "stripe.webhooks.constructEvent"
      idempotency_header: "Idempotency-Key"
      success_status: 200
      retry_on: [500, 502, 503, 504]
      reconciliation_window_hours: 24
      supports_3ds: true
      supports_setup_future_usage: true

    mercadopago:
      webhook_signature_header: "x-signature"
      webhook_signature_lib: "@mercadopago/sdk-js"
      idempotency_header: "X-Idempotency-Key"
      success_status: [200, 422]      # 422 = "já processei"
      retry_on: [500, 503]
      reconciliation_window_hours: 48
      brazilian_specific: true        # PIX nativo

    pagseguro:
      webhook_signature_header: "x-pagseguro-signature"
      legacy_soap_endpoints: true     # alguns endpoints legacy
      success_status: 200

    pix_direct:
      psp: "itau"                     # ou bradesco, sicredi, etc
      uses_dict: true                  # lookup de chave PIX
      qrcode_expiration_minutes: 15

  required_pii_redaction:
    # Campos que NUNCA podem ir em log (extra além de PAN/CVV)
    - cpf
    - cnpj
    - phone
    - address.line1

  exempt_from_idempotency:
    # POSTs de payment que NÃO precisam de header (já é idempotent)
    - "/payments/refunds/list"        # GET-shaped POST
    - "/payments/calculate-fees"      # cálculo readonly

  reconciliation_skip_test_mode:
    # NÃO conciliar tx em modo test (Stripe test mode etc)
    - "tx_id startswith 'ch_test_'"
    - "metadata.environment == 'test'"

  refund_audit_required: true         # sempre exige justificativa ≥ 10 chars
```

### Auto-detecção

- Detecta gateway por imports: `from 'stripe'` → ativa profile Stripe
- Detecta PIX: env `PIX_DICT_KEY` ou import `@bacen/pix` → ativa PIX
- Detecta modo test: `STRIPE_SECRET_KEY` começa com `sk_test_` → relaxa reconciliação

### Profile-aware validation

Sem este sistema, blindar acusava "webhook não verifica signature" em
Mercado Pago olhando padrão Stripe. Agora ele sabe que MP usa
`x-signature` (header diferente) e a lib correspondente.

### Markers em payment handlers

```ts
/**
 * @blindar:gateway-stripe
 * @blindar:idempotency-handled-by-stripe
 */
@Post('payments/intent')
async createIntent(@Body() dto, @Headers('idempotency-key') key) {
  // ...
}

/**
 * @blindar:gateway-pagseguro
 * @blindar:legacy-soap-endpoint
 */
@Post('pagseguro/notification')
async pagseguroLegacyWebhook(@Body() xml: string) {
  // ...
}
```

## Anti-padrões (alguns são CVE-grade / PCI violation)

- ❌ Aceitar `amount` do cliente sem validar com DB
- ❌ Float/decimal pra valor (use BIGINT cents)
- ❌ Logar PAN/CVV (PCI level 1 instantâneo)
- ❌ Webhook sem signature verify (qualquer um cria payment "paid")
- ❌ Webhook sem dedup (paga 2x na mesma compra)
- ❌ Webhook síncrono > 5s (gateway marca falha + retenta)
- ❌ Sem idempotency em POST payment (network flake = cobrar 2x)
- ❌ Refund via UPDATE direto no DB (sem chamar gateway)
- ❌ Sem reconciliação (descobre divergência em chargeback)
- ❌ Mudar status sem audit (não consegue investigar)
- ❌ Hardcode `STRIPE_SECRET_KEY` em código (env + rotação)
- ❌ Mesmo idempotency_key reusado em pedidos diferentes (conflict silencioso)
