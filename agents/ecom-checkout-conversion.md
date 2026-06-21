---
name: ecom-checkout-conversion
category: vertical
module: 8
priority: P1
description: |
  Checkout/conversão e-commerce. Cobre cart abandonment (persist, retry,
  recovery), 3DS2 (Strong Customer Authentication acima de R$ 500),
  Apple Pay / Google Pay (conversão mobile), anti-fraude (Stripe Radar,
  Cybersource, Konduto), one-tap checkout, address autocomplete (ViaCEP),
  multi-step vs single-page, calculo de frete pré-checkout, retry com
  método alternativo. Roda quando integração de e-commerce/checkout for
  detectada.
---

# Agent: ecom-checkout-conversion

## Missão

Cada etapa de checkout custa **7-10% de conversão**. Cada cart perdido
no refresh custa o usuário inteiro. Este agente audita os 10 pontos
mais críticos de conversão em checkout BR — não é "bom ter", é receita
deixando de entrar.

## Quando rodar

- Módulo 8 selecionado E projeto tem e-commerce/checkout
- Detectado: `stripe`, `mercadopago`, `pagseguro`, `cielo`, `getnet`,
  `paypal`, `@adyen` em `package.json`
- Detectado: rotas `/checkout`, `/cart`, `/carrinho`, `/finalizar-compra`
- Detectado: componentes `<Checkout>`, `<Cart>`, `<PaymentForm>`
- Operador pediu "checkout", "carrinho", "conversão"

## A. Princípios de conversão (não-negociáveis)

1. **Carrinho persiste**: refresh, troca de aba, sleep no celular não
   pode perder itens (localStorage + sync com BE se logado)
2. **Frete antes do checkout**: cliente sabe valor total **antes** de
   preencher dado pessoal (abandono cai ~30%)
3. **Multi-step ≤ 3 etapas**: cada etapa extra = -7% conversão
4. **Apple/Google Pay em mobile**: -50% tempo de checkout, +20% conversão
5. **3DS2 só quando exigido**: R$ 500+, primeiro pagamento, comportamento
   suspeito (não em toda transação — atrito desnecessário)
6. **Retry com método alternativo**: cartão recusou → oferecer PIX/boleto
   na mesma tela
7. **Address autocomplete (ViaCEP)**: CEP → preenche endereço sozinho

## B. Cart abandonment — recovery flow

### B.1 Persist obrigatório

```ts
// localStorage + cookie + sync com BE se logado
const cart = useCartStore();
useEffect(() => {
  // Hydrate de localStorage no mount
  cart.hydrate();
  // Sync com BE a cada mudança (debounced 500ms)
  return cart.subscribe(debounce(() => {
    if (isLoggedIn) api.cart.sync(cart.items);
  }, 500));
}, []);
```

### B.2 Recovery por email/WhatsApp

- T+1h: email "ainda interessado?"
- T+24h: email com cupom 5%
- T+72h: WhatsApp (se opt-in) com cupom 10%
- Tracking UTM em cada link pra medir recuperação

### B.3 Stock reservation

Se item escasso, reservar **15min** após adicionar ao carrinho (evita
"vendi, mas era o último, e agora?"). Liberar se carrinho não converter.

## C. 3DS2 (Strong Customer Authentication)

### C.1 Quando aplicar

| Cenário | 3DS2? |
|---|---|
| < R$ 500 | Opcional (não aplicar — atrito mata conversão) |
| ≥ R$ 500 | Obrigatório (BCB Circular 3978) |
| Primeiro pagamento do cliente | Sim (anti-fraude) |
| Card emissor europeu | Sempre (PSD2 EU) |
| Score Stripe Radar > 65 | Sim |

### C.2 Frictionless vs Challenge

3DS2 tenta **frictionless** primeiro (issuer aprova sem desafio). Se
challenge → modal/iframe do banco (pode ser senha, SMS, app). Suportar
ambos no front:

```ts
const intent = await stripe.confirmCardPayment(clientSecret, {
  payment_method: { card: cardElement },
});
if (intent.error?.type === 'card_error' && intent.error.code === 'authentication_required') {
  // Re-tentar com handleCardAction
  await stripe.handleCardAction(clientSecret);
}
```

## D. Apple Pay / Google Pay

### D.1 Setup

- Domain verification (Apple) — arquivo em `.well-known/apple-developer-merchantid-domain-association`
- Google Pay merchant ID + processor (Stripe/Adyen/MP)
- `<PaymentRequestButton />` (Stripe) ou Web Payments API direto

### D.2 Por que importa

| Métrica | Cartão manual | Apple Pay |
|---|---|---|
| Tempo checkout | 90s | 12s |
| Conversão mobile | 2% | 4-6% |
| Cart abandonment | 70% | 35% |

Não ter Apple/Google Pay em mobile = **deixar metade da receita mobile
na mesa**.

## E. Anti-fraude

| Ferramenta | Plug | Custo |
|---|---|---|
| Stripe Radar | Builtin Stripe | 0,05 USD/tx |
| Cybersource | Adyen, custom | Pré-pago |
| Konduto | API direta BR | Por TX |
| ClearSale | API direta BR | Por TX |

Sinais que devem disparar review:

- Email descartável (mailinator, tempmail)
- CPF/email/IP em blacklist (chargebacks anteriores)
- Geo do IP ≠ país do BIN do cartão
- Velocity: > 3 cartões diferentes em 10min mesmo device
- Tentativa em horário atípico (3-5am)
- Endereço de entrega ≠ endereço do cartão (CPF)

## F. Address autocomplete (BR)

```ts
// ViaCEP grátis, sem auth
const fetchAddress = async (cep: string) => {
  const res = await fetch(`https://viacep.com.br/ws/${cep}/json/`);
  const data = await res.json();
  if (data.erro) throw new Error('CEP inválido');
  return { rua: data.logradouro, bairro: data.bairro, cidade: data.localidade, uf: data.uf };
};
```

Fallback: BrasilAPI, Correios SOAP (lento, exige user/pass).

## G. Calculo de frete pré-checkout

Mostrar frete **na página do produto** ou **na sacola**, NUNCA esperar
o checkout. Integração:

- Correios SOAP (PAC/Sedex) — lento, instável
- Melhor Envio (API) — multi-transportadora, agregador
- Frenet, Kangu, JadLog API
- Frete grátis acima de X (configurável)

## H. One-tap / saved payment methods

Cliente logado com cartão salvo:

```ts
@Post('checkout/one-tap')
async oneTap(@User() user, @Body() { product_id, payment_method_id }) {
  // Validar que payment_method pertence ao user
  if (!user.payment_methods.includes(payment_method_id)) throw new Forbidden();
  // Charge usando MP/Stripe setup_future_usage='off_session'
  return paymentService.charge({ user, product_id, payment_method_id });
}
```

## I. Multi-step vs single-page

| Modelo | Conversão | Quando usar |
|---|---|---|
| Single-page (1 tela tudo) | +15% | Ticket baixo, produto simples |
| 3-step (cart → endereço → pagamento) | Baseline | Default |
| 5+ steps | -30% | NUNCA — refactor obrigatório |

## J. Greps obrigatórios

```bash
# Form sem autocomplete cc-* (bloqueia auto-fill)
rg -n "<input.*name=['\"]?(card|cc).*number" --type tsx --type jsx --type html | rg -v "autocomplete"

# Currency display sem locale
rg -n "toFixed\(2\)" --type ts --type tsx | rg -v "(toLocaleString|Intl\.NumberFormat)"

# 3DS2 não configurado
rg -n "payment_method_types.*card" --type ts | rg -v "(request_three_d_secure|three_d_secure)"

# Cart sem persist
rg -l "useCart|cartStore" --type ts --type tsx | xargs grep -L -E "(localStorage|persist|hydrate)"

# Apple Pay / Google Pay ausentes
rg -l "PaymentRequestButton|applepay|googlepay|google-pay" --type ts --type tsx
```

## K. Output esperado em sec.html

```
┌─ E-com Checkout (Módulo 8) ───────────────────────────────┐
│ Cart persiste (refresh-safe)    : ✓ localStorage + sync   │
│ Multi-step ≤ 3 etapas           : ✓ 3 etapas              │
│ Form autocomplete cc-*          : ✓ todos campos          │
│ 3DS2 ativo > R$ 500             : ✓                       │
│ Apple Pay configurado           : ✓ domain verified       │
│ Google Pay configurado          : ✓                       │
│ Anti-fraude (Radar/Konduto)     : ✓ Stripe Radar          │
│ Retry com método alternativo    : ✓ PIX/boleto fallback   │
│ ViaCEP autocomplete             : ✓ + fallback BrasilAPI  │
│ Frete pré-checkout              : ✓ na sacola             │
│ Currency em pt-BR locale        : ✓ R$ 1.234,56           │
│ Status                          : ✓ CONVERSION-READY      │
└───────────────────────────────────────────────────────────┘
```

## L. Anti-padrões (perda de receita garantida)

- ❌ Checkout > 3 etapas (-7% por etapa)
- ❌ Cart sem persist (refresh limpa carrinho)
- ❌ Form `cc-number` sem `autocomplete` (bloqueia auto-fill iOS/Chrome)
- ❌ 3DS2 em toda compra (-15% conversão; só > R$ 500)
- ❌ 3DS2 ausente > R$ 500 (risco fraude + multa BACEN)
- ❌ Sem Apple/Google Pay em mobile (perde metade da receita mobile)
- ❌ Frete só no fim do checkout (-30% conversão)
- ❌ Cartão recusou e não oferece PIX/boleto (perde a venda inteira)
- ❌ CEP sem ViaCEP (cliente digita endereço completo manualmente)
- ❌ Currency `R$ 1,234.56` ao invés de `R$ 1.234,56` (parece site gringo)
- ❌ Stock não reserva (cliente paga, descobre que esgotou)
- ❌ Sem recovery email/WhatsApp pra cart abandonado

## M. Cross-references

- `agents/payments.md` — gateway/idempotência/webhook (camada técnica)
- `agents/fintech-banking-br.md` — PIX detalhado, Open Finance
- `agents/responsive-a11y.md` — touch targets ≥ 44px no checkout mobile
- `agents/i18n-tz.md` — pt-BR locale para currency
