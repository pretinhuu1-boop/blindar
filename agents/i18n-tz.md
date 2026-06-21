---
name: i18n-tz
category: frontend
module: 10
priority: P1
description: |
  Internacionalização e timezones corretos desde o dia 1. Tudo em UTC no
  banco (TIMESTAMPTZ), currency em cents (BIGINT), timezone IANA por
  usuário, ICU MessageFormat pra plurais/gênero, RTL pra ar/he, locale
  detection respeitando preferência do user. Bug de timezone é o #1 que
  aparece em produção; este agente previne.
---

# Agent: i18n-tz

## Missão

Aplicação web 2026 nasce global. Mesmo MVP pra Brasil tem cliente em
fuso diferente, formato de data confuso entre regiões, expansão pra outros
idiomas vira refator caro. Decisão certa no dia 1 = zero retrabalho.

## Quando rodar

- Módulo 10 selecionado E `ui_detected: true`
- Operador pediu "internacional" / "global" / "timezone" / "i18n"
- Projeto em produção tem usuários em mais de 1 fuso

## A. Timezones (a fonte #1 de bug em prod)

### Regras absolutas

1. **DB sempre UTC** — `TIMESTAMPTZ` no Postgres, `DATETIME` UTC no MySQL
2. **API responde ISO 8601 com offset** — `2026-06-14T14:30:00Z` ou `+00:00`
3. **Frontend converte na hora de exibir** usando timezone do user
4. **Timezone do user é IANA**: `America/Sao_Paulo`, NUNCA `GMT-3` (não respeita DST)
5. **NUNCA** somar/subtrair horas pra "converter" — use `Intl.DateTimeFormat` ou Temporal API

### Coluna obrigatória

```sql
ALTER TABLE users ADD COLUMN timezone TEXT NOT NULL DEFAULT 'America/Sao_Paulo';
-- Validar contra lista IANA: Intl.supportedValuesOf('timeZone')
```

### Frontend — render

```ts
// Use Temporal API (TC39 stage 3, polyfill disponível) OU Intl.DateTimeFormat
const utcInstant = '2026-06-14T14:30:00Z';
const userTz = user.timezone;  // 'America/Sao_Paulo'

new Intl.DateTimeFormat('pt-BR', {
  timeZone: userTz,
  dateStyle: 'medium',
  timeStyle: 'short'
}).format(new Date(utcInstant));
// → "14 de jun. de 2026, 11:30"
```

### Edge cases que pegam todo mundo

- **Horário de verão**: DST muda 2x/ano em ~70 países (Brasil aboliu em 2019,
  mas EUA/EU mantêm). Soma de "1 dia" em moment.js dá errado nos dias de
  transição. Use Temporal API ou `date-fns-tz`.
- **Cliente envia "amanhã 10h"** — perguntar timezone do cliente (não do
  servidor) e converter pra UTC só ao salvar.
- **Agenda recorrente** — armazenar regra (RRULE iCalendar RFC 5545) + tz,
  não datas expandidas. Caso contrário DST quebra séries longas.
- **Histórico em UTC, exibição em local** — relatório "vendas de
  segunda-feira" varia conforme timezone do user pedindo.

### Greps

```bash
# Detecta uso direto de Date sem timezone
rg -n "new Date\(['\"][0-9]{4}-[0-9]{2}" --type ts

# Detecta moment().add('hours', N) pra conversão de TZ
rg -n "moment\(.*\)\.(add|subtract)\(.*hour" --type ts --type js

# Detecta strings tipo "America/" ou "Europe/" hardcoded (tz por user, não global)
rg -n "['\"](America|Europe|Asia|Africa|Australia|Pacific)/[A-Z][a-z_]+['\"]" \
   --type ts --type js -g '!*.test.*'

# Detecta DATETIME sem TIMESTAMPTZ no Postgres
rg -n "TIMESTAMP\s+WITHOUT" --type sql
rg -n "DATETIME(?!.*UTC)" --type sql --type ts
```

## B. Currency

### Regras

1. **Armazenar em centavos (BIGINT)** — `1500` = R$ 15,00 (nunca `15.00` `FLOAT`)
2. **Coluna separada `currency CHAR(3)`** — ISO 4217 (`BRL`, `USD`, `EUR`)
3. **Conversão entre moedas** — tabela `exchange_rates(from, to, rate, effective_at)`
4. **Render no client** com `Intl.NumberFormat(locale, { style: 'currency', currency })`
5. **NUNCA** arredondar no client antes de enviar — backend é fonte de verdade

```ts
new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' })
  .format(1500 / 100);   // "R$ 15,00"

new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' })
  .format(15.99);        // "$15.99"
```

### Por que não DECIMAL

- Aritmética de DECIMAL em JS perde precision (vira number ≠ BigInt)
- BIGINT cents sempre exato, soma/multiplicação trivial
- Comparações `===` funcionam
- Padrão Stripe, PayPal, Mercado Pago — todos retornam cents

## C. Idiomas

### Stack recomendada

| Lib | Quando |
|---|---|
| `next-intl` | Next.js — recomendado em 2026 |
| `@formatjs/intl` | React puro — usa Intl nativo |
| `vue-i18n` | Vue |
| `i18next` | universal, mais flexível, mais peso |

**NÃO** usar `react-intl` antigo (mantenance mode).

### ICU MessageFormat (plurais + gênero + escolhas)

```
"appointments.count": "{count, plural, =0 {Nenhum agendamento} =1 {1 agendamento} other {# agendamentos}}"

"user.greeting": "Olá, {gender, select, male {Sr.} female {Sra.} other {}} {name}!"

"file.size": "Tamanho: {bytes, number, ::compact-short unit/byte}"
```

NUNCA concatenar strings (`"Você tem " + count + " items"`) — quebra plurais
em russo/polonês/árabe (5+ formas).

### Estrutura de arquivos

```
locales/
├── pt-BR/
│   ├── common.json
│   ├── appointments.json
│   └── billing.json
├── en-US/
│   ├── common.json
│   ├── appointments.json
│   └── billing.json
└── es-ES/
    └── ...
```

### Fallback chain

```ts
// pt → pt-BR → en-US (default)
i18n.fallbackLng = {
  'pt': ['pt-BR', 'en-US'],
  default: ['en-US']
};
```

### Detecção de locale

Ordem de precedência:
1. Preferência salva no perfil do user (`users.locale`)
2. Cookie `NEXT_LOCALE` (set explicit pelo user)
3. URL prefix `/en-US/...` ou subdomain
4. `Accept-Language` do browser
5. Default global

NUNCA por IP/geolocation (user em viagem quer SUA língua, não a do país).

## D. Validação de keys missing (CI)

Toda chave em uso deve existir em **todos** os locales:

```bash
# Script de validação
node scripts/validate-i18n.js
# Falha se:
# - chave usada em código mas não em locales/
# - chave em locales/pt-BR mas não em locales/en-US (ou vice-versa)
# - ICU malformado
```

Lib útil: `i18next-parser` extrai chaves automaticamente.

## E. RTL (right-to-left)

Necessário pra: árabe, hebraico, persa, urdu, sindhi.

### CSS

```css
html { direction: ltr; }
html[dir="rtl"] { direction: rtl; }

/* Use propriedades logical, não left/right */
.card {
  margin-inline-start: 16px;   /* não margin-left */
  padding-inline-end: 8px;     /* não padding-right */
  border-start-start-radius: 4px;
}
```

### Lib

- Tailwind: `tailwindcss-rtl` plugin OU usar `ms-4`/`me-4` (logical) em vez de `ml-4`/`mr-4`
- Componentes próprios: testar com `dir="rtl"` no `<html>` em dev

### Greps

```bash
# Detecta left/right físicos (deveriam ser logical)
rg -n "(margin-left|margin-right|padding-left|padding-right|border-left|border-right):" \
   --type css --type tsx --type ts
```

## F. Number / date formatting per locale

```ts
// Numbers
new Intl.NumberFormat('pt-BR').format(1234567.89);   // "1.234.567,89"
new Intl.NumberFormat('en-US').format(1234567.89);   // "1,234,567.89"

// Relative time ("há 3 dias", "in 2 hours")
new Intl.RelativeTimeFormat('pt-BR', { numeric: 'auto' }).format(-3, 'day');
// → "anteontem" (não "há 3 dias" porque "anteontem" existe em pt-BR!)

// List formatting ("A, B e C" vs "A, B, and C")
new Intl.ListFormat('pt-BR', { type: 'conjunction' }).format(['A','B','C']);
// → "A, B e C"
```

Lib `@formatjs/intl-relativetimeformat` polyfill se precisar.

## G. Telefone

### Regras

- Armazenar **E.164** sempre: `+5511987654321`
- Validar com `libphonenumber-js` (Google)
- Render usando `formatNumber(phone, 'NATIONAL')` ou `'INTERNATIONAL'`
- Detectar país por DDI no input

```ts
import { parsePhoneNumber } from 'libphonenumber-js';
const phone = parsePhoneNumber('11987654321', 'BR');
phone.format('E.164');         // '+5511987654321' (salvar isso)
phone.formatNational();        // '(11) 98765-4321' (exibir)
phone.formatInternational();   // '+55 11 98765-4321'
```

## H. Endereço

NÃO assumir formato fixo (CEP brasileiro ≠ ZIP code americano ≠ UK postcode).

```sql
CREATE TABLE addresses (
  id          UUID PRIMARY KEY,
  user_id     UUID NOT NULL,
  country     CHAR(2) NOT NULL,    -- ISO 3166-1 alpha-2
  state       TEXT,                -- estado/província/region
  city        TEXT NOT NULL,
  postal_code TEXT,                -- variável: 8 dig BR, 5 US, alfanum UK
  line1       TEXT NOT NULL,       -- rua + número
  line2       TEXT,                -- complemento
  raw         JSONB                -- payload original do autocomplete
);
```

Use **Google Places** ou **here.com** pra autocomplete e validação.

## I. Output esperado em sec.html

```
┌─ i18n + Timezones (Módulo 10) ───────────────────────────┐
│ DB colunas datetime          : 100% TIMESTAMPTZ ✅        │
│ users.timezone (IANA)         : ✅ obrigatória            │
│ Currency em cents (BIGINT)    : ✅ 7/7 tabelas            │
│ Locales suportados            : pt-BR, en-US, es-ES       │
│ Cobertura de chaves           : 100% em todos os locales  │
│ ICU MessageFormat (plurais)   : ✅ usado, sem concat      │
│ Telefone E.164                : ✅ libphonenumber         │
│ Endereço formato variável     : ✅ não-fixo               │
│ RTL ready                     : ✅ CSS logical properties │
│ Locale detection              : profile→cookie→header     │
│ Relative time / List / Number : ✅ Intl nativo            │
│ Status                        : ✅ PRODUCTION-READY      │
└───────────────────────────────────────────────────────────┘
```

## Anti-padrões (alto custo de correção)

- ❌ `DATETIME` sem timezone no banco (vira pesadelo regulatório)
- ❌ Salvar timezone como offset (`GMT-3`) em vez de IANA
- ❌ Aritmética de horas pra converter timezone
- ❌ Currency em `FLOAT`/`DECIMAL` no client
- ❌ Concatenar string pra plural (`count + " items"`)
- ❌ `react-intl` antigo em projeto novo (use `next-intl` ou `@formatjs/intl`)
- ❌ Detectar locale por IP (user em viagem fica frustrado)
- ❌ `margin-left` em vez de `margin-inline-start` (quebra RTL)
- ❌ Telefone como `(11) 99...` em string (não consegue dial cross-country)
- ❌ CEP/ZIP em campo fixo VARCHAR(8) (não cabe US ZIP+4 nem UK postcode)
- ❌ Locale hardcoded em código (`Intl.NumberFormat('pt-BR', ...)` em vez de user.locale)
- ❌ DST hardcoded como `-3` (Brasil mudou em 2019, código continuou errado)

## Interação com outros agentes

- **db-architect** garante `TIMESTAMPTZ`, `BIGINT` cents, `users.timezone`
- **config-externalization** garante que strings de UI estão em locales/, não em código
- **api-design** garante que API responde ISO 8601 com offset, currency como int
- **auth-premium** usa `users.locale` pra email de notificação no idioma certo
