---
name: email-deliverability
category: ops
module: 14
priority: P1
description: |
  Email mandado é email que CHEGA na caixa de entrada (não no spam). Cobre:
  DKIM/SPF/DMARC obrigatórios + monitorados, bounce/complaint handling
  (lista de supressão automática), warm-up de IP/domínio novo, IPs
  separados (transacional vs marketing), reputação tracking, unsubscribe
  obrigatório em marketing, footer compliant LGPD/CAN-SPAM, deliverability
  > 95% como gate.
---

# Agent: email-deliverability

## Missão

Sem DKIM/SPF/DMARC = vai pra spam. Sem bounce handling = manda 100x pra
endereço morto = IP marcado = TODOS os emails viram spam. Sem
unsubscribe = multa LGPD/CAN-SPAM. Este agente prescreve operação que
**chega**.

## Quando rodar

- Módulo 14 selecionado
- Projeto manda email (transacional ou marketing)
- Detectado: `nodemailer` / `resend` / `@sendgrid/mail` / `aws-sdk ses` / `postmark`

## A. DNS records obrigatórios

### SPF (Sender Policy Framework)

```dns
example.com.  TXT  "v=spf1 include:_spf.resend.com include:amazonses.com -all"
```

Declara: "esses servidores podem mandar email em meu nome". `-all` no fim
diz "rejeita o resto" (não `~all` soft fail).

### DKIM (DomainKeys Identified Mail)

```dns
resend._domainkey.example.com.  TXT  "v=DKIM1; k=rsa; p=MIGfMA0GCSqGSIb..."
```

Provider gera. Assinatura criptográfica garante que email não foi
adulterado e veio do domínio.

### DMARC (autenticação + política)

```dns
_dmarc.example.com.  TXT  "v=DMARC1; p=reject; rua=mailto:dmarc@example.com; ruf=mailto:dmarc@example.com; sp=reject; aspf=s; adkim=s"
```

`p=reject` (não `none`/`quarantine`) — bloqueia falsificação direto.
**Subir gradual:** começa `p=none` (monitor 30d), passa `p=quarantine`
(30d), termina `p=reject`.

### BIMI (Brand Indicators for Message Identification) — opcional, ganho de marca

```dns
default._bimi.example.com.  TXT  "v=BIMI1; l=https://example.com/logo.svg; a=https://example.com/vmc.pem"
```

Mostra logo da marca no Gmail/Yahoo. Requer DMARC `p=reject` + VMC certificate.

## B. Verificação automatizada

```bash
# Em CI / health check
dig +short TXT example.com | grep "v=spf1"
dig +short TXT default._domainkey.example.com | grep "v=DKIM1"
dig +short TXT _dmarc.example.com | grep "v=DMARC1"

# Tools online: mxtoolbox.com, mail-tester.com (score /10)
```

Alerta se algum sumir.

## C. Bounce / complaint / supressão

### Tipos de bounce

| Tipo | Ação |
|---|---|
| Hard bounce (550 user unknown) | **Remover imediato** da lista, marcar `email_invalid` |
| Soft bounce (4xx temporary) | Retry exponencial (5min/30min/1h), após 3 falhas marca soft-suppressed |
| Complaint (user clicou "spam") | **Remover imediato** + log, NUNCA reenviar |
| Out-of-office | Não suprimir |

### Tabela de supressão

```sql
CREATE TABLE email_suppressions (
  email      TEXT PRIMARY KEY,
  reason     TEXT NOT NULL,        -- 'hard_bounce', 'complaint', 'unsubscribe', 'manual'
  source     TEXT NOT NULL,        -- 'ses_event', 'webhook', 'manual'
  suppressed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at TIMESTAMPTZ,           -- só pra unsubscribe que pode voltar
  meta       JSONB
);
```

**Verificar ANTES de cada envio**:
```ts
if (await db.emailSuppression.findUnique({ where: { email: to } })) {
  return { skipped: true, reason: 'suppressed' };
}
```

### Webhook handlers

```ts
// SES SNS / Resend webhook / SendGrid event
@Post('webhooks/email')
async handle(@Body() event) {
  switch (event.type) {
    case 'bounce':
      if (event.bounceType === 'Permanent') {
        await suppress(event.recipient, 'hard_bounce', 'ses_event');
      }
      break;
    case 'complaint':
      await suppress(event.recipient, 'complaint', 'ses_event');
      await alertOps({ complaintRate: await getComplaintRate24h() });
      break;
    case 'delivery':
      await logDelivery(event);
      break;
  }
}
```

## D. Warm-up de IP/domínio novo

Domínio/IP novo manda > 1000 emails de uma vez → marca como spam.
Cronograma:

| Dia | Volume |
|---|---|
| 1-3 | 50/dia |
| 4-7 | 200/dia |
| 8-14 | 500/dia |
| 15-21 | 2000/dia |
| 22+ | volume normal |

Manda pros **mais engajados primeiro** (abriram, clicaram). Pula
desconhecidos no início.

## E. IPs separados (TRANSACIONAL vs MARKETING)

| Tipo | IP/subdomínio | Importância |
|---|---|---|
| **Transacional** (confirmação, reset, recibo) | `mail.example.com` | CRÍTICO — não pode atrasar |
| **Marketing** (newsletter, promoção) | `news.example.com` | Pode atrasar, NÃO pode atrapalhar transacional |

**NUNCA misturar.** Complaint em marketing não derruba reputação do
transacional.

## F. Footer compliant

### LGPD / CAN-SPAM / GDPR — todo email marketing exige:

- **Identificação clara do remetente** (empresa, CNPJ se BR)
- **Endereço físico** (CAN-SPAM US, recomendado LGPD)
- **Link de unsubscribe** funcional (1 clique idealmente — RFC 8058)
- **Motivo** ("você recebeu porque se cadastrou em X")
- **Política de privacidade** linkada

```html
<footer>
  Você recebeu este email porque se cadastrou em <a>example.com</a>.
  <br>Salon Pro Tecnologia LTDA · Rua Exemplo, 123 · São Paulo, SP · CNPJ 00.000.000/0001-00
  <br><a href="{{unsubscribe_url}}">Cancelar inscrição em 1 clique</a> ·
       <a href="/privacy">Política de Privacidade</a>
</footer>
```

### One-click unsubscribe (Gmail/Yahoo exigem desde 2024)

```
Headers:
List-Unsubscribe: <mailto:unsub@example.com?subject={{id}}>, <https://example.com/u/{{token}}>
List-Unsubscribe-Post: List-Unsubscribe=One-Click
```

Botão "Cancelar inscrição" do Gmail vira ação direta, sem confirmação.

## G. Reputação e métricas

| Métrica | Meta | Alerta |
|---|---|---|
| Delivery rate | > 98% | < 95% |
| Open rate (transacional) | > 50% | < 30% |
| Open rate (marketing) | > 20% | < 10% |
| Click rate | > 2% | < 0.5% |
| Bounce rate | < 2% | > 5% (gateway pode bloquear acima de 5%) |
| Complaint rate | < 0.1% | > 0.3% (gateway bloqueia acima de 0.5%) |
| Unsubscribe rate | < 0.5% | > 2% |

### Dashboards

- **Google Postmaster Tools** (gratuito) — reputação em Gmail
- **SNDS** (Microsoft) — Outlook/Hotmail
- **Provider dashboard** (SES, Resend, SendGrid)

## H. Templates em DB/CMS, não código

Já coberto em `config-externalization`. Resumo:

```sql
CREATE TABLE email_templates (
  key        TEXT NOT NULL,
  locale     CHAR(5) NOT NULL,
  subject    TEXT NOT NULL,
  body_html  TEXT NOT NULL,
  body_text  TEXT NOT NULL,         -- obrigatório (a11y + deliverability)
  variables  JSONB,
  version    INTEGER NOT NULL DEFAULT 1,
  UNIQUE (key, locale)
);
```

**Plain text obrigatório** (sem ele, spam score sobe).

### Render

- **MJML** ou **React Email** pra HTML responsivo
- Testar em **Litmus** / **Email on Acid** (Outlook é dor)
- **Dark mode** support (`prefers-color-scheme`)
- **Imagens com alt** (e fallback se bloqueadas — muitos clients bloqueiam por default)

## I. Fila + retry + fallback provider

```ts
// Fila assíncrona — nunca bloquear request
@Process('email')
async send(job: { to, template, data }) {
  // 1. Check supressão
  if (await isSuppressed(job.to)) return { skipped: 'suppressed' };

  // 2. Tenta provider primário
  try {
    return await resend.send({ /* ... */ });
  } catch (err) {
    if (err.code === 'rate_limited') throw err;  // retry com backoff
    // 3. Fallback provider secundário
    return await ses.send({ /* ... */ });
  }
}
```

## J. Greps obrigatórios

```bash
# Email body em string literal (deveria estar em DB)
rg -nU "['\"]Olá[^'\"]{50,}['\"]" --type ts -g '!templates/'

# Sem verificação de supressão antes do envio
rg -n "(resend|ses|sendgrid).*\.send\(" --type ts | rg -v "(suppress|isSuppressed)"

# Sem unsubscribe em marketing
rg -nU "marketing|newsletter|promo" --type ts -A 20 | rg -v "(unsubscribe|List-Unsubscribe)"

# Hard-coded sender domain (deveria ser env)
rg -n "from:.*['\"].*@.*\.(com|br)['\"]" --type ts
```

## Output esperado em sec.html

```
┌─ Email Deliverability (Módulo 14) ───────────────────────┐
│ SPF record                    : ✅ -all                    │
│ DKIM signed                   : ✅ key verified           │
│ DMARC p=reject                : ✅                         │
│ BIMI (logo na inbox)          : ⚠ opcional                │
│ Bounce handler                : ✅ webhook ativo          │
│ Complaint handler             : ✅ + alerta > 0.3%        │
│ Tabela de supressão           : ✅ check antes envio      │
│ IPs separados (tx vs mkt)     : ✅ mail. e news.          │
│ One-click unsubscribe         : ✅ List-Unsubscribe-Post  │
│ Footer compliant LGPD         : ✅                         │
│ Plain text version            : ✅ obrigatório            │
│ Postmaster Tools verificado   : ✅                         │
│ Delivery rate (30d)           : 98.7% ✅                   │
│ Bounce rate (30d)             : 0.8% ✅                    │
│ Complaint rate (30d)          : 0.04% ✅                   │
│ Fallback provider             : ✅ SES → Resend           │
│ Status                        : ✅ DELIVERED              │
└───────────────────────────────────────────────────────────┘
```

## Intelligence (⭐ v0.21) — env-aware (rules diferentes por ambiente)

Em dev, exigir DMARC `p=reject` é impossível (você usa Mailtrap/Mailpit
ou similar). Em prod é obrigatório. Lê `.blindar/intelligence.yml`:

```yaml
email-deliverability:
  environments:
    development:
      provider: mailpit            # ou mailtrap, mailcatcher
      skip_checks:
        - dmarc_record
        - dkim_signing
        - spf_record
        - bounce_handling
        - warmup_required
        - one_click_unsubscribe
      # Em dev, blindar NÃO acusa falta dessas configurações

    staging:
      provider: resend
      use_subdomain: staging-mail.example.com
      skip_checks:
        - warmup_required          # subdomain dedicado, não precisa
      relaxed_thresholds:
        delivery_rate_min: 90      # vs 98 em prod
        bounce_rate_max: 5         # vs 2 em prod

    production:
      strict: true                 # todas as regras valem

  ip_warmup_grace_period_days: 30
  # Não acusa "volume baixo" nos primeiros 30 dias após IP novo

  marketing_emails_separate_domain:
    required: true
    pattern: "news.*"              # subdomínio news.example.com pra marketing

  transactional_exempt_from:
    # Emails transacionais não precisam de:
    - one_click_unsubscribe        # CAN-SPAM exempt
    - physical_address             # se não for marketing
    - "consent_required"           # já é contrato

  template_safe_list:
    # Templates que NÃO geram aviso de "sem unsubscribe"
    - "password-reset"
    - "email-verification"
    - "payment-receipt"
    - "appointment-confirmation"
    - "appointment-reminder"
    - "security-alert"

  inline_override_marker_html: "<!-- @blindar:transactional -->"
```

### Markers nos templates

```html
<!-- @blindar:transactional -- não precisa de unsubscribe -->
<html>
<body>
  Seu agendamento foi confirmado para amanhã 14h.
</body>
</html>
```

### Auto-detecção

- Provider `mailpit`/`mailtrap` em `.env` → modo dev (não acusa DKIM)
- Subdomínio `staging-*` no `MAIL_FROM` → modo staging (regras relaxed)
- Template name contém `welcome`, `reset`, `verify`, `receipt`, `reminder`, `confirmation` → transacional (não exige unsubscribe)

### Mudança de comportamento entre ambientes

Antes (v0.20): blindar acusava em DEV "DMARC ausente" → operador frustrado.
Agora (v0.21): blindar só exige em prod (ou env explicitamente strict).

```bash
# Variável de ambiente
BLINDAR_ENV=production            # força modo strict
BLINDAR_ENV=development           # modo permissivo (default se NODE_ENV=dev)
```

## Anti-padrões

- ❌ Sem SPF/DKIM/DMARC (60%+ vão pra spam)
- ❌ DMARC `p=none` permanente (não protege contra spoofing)
- ❌ Mandar pra hard bounce 100 vezes (IP queima)
- ❌ Misturar IP transacional e marketing
- ❌ Sem unsubscribe em marketing (multa LGPD/CAN-SPAM)
- ❌ Unsubscribe que pede confirmação (Gmail exige 1-click)
- ❌ Template hardcoded no código
- ❌ Sem plain text (spam score +2)
- ❌ Volume alto em IP novo sem warm-up
- ❌ Bounce rate > 5% sem ação (gateway bloqueia conta)
- ❌ Reply-to `no-reply@` (acessibilidade ruim + spam signal)
- ❌ Imagem com `src="http://..."` sem alt em email
