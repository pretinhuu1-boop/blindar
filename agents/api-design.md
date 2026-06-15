---
name: api-design
category: api
module: 4
priority: P1
description: |
  Cobre design correto de API REST/GraphQL/Webhook: OpenAPI como fonte de
  verdade, versionamento, idempotency keys, paginação cursor, filtragem
  RSQL/FIQL, ETags, RFC 7807 Problem Details, contract testing (Pact),
  webhook signature + retry + ordering, rate limit headers. Bloqueia
  release se contrato não cobre o implementado.
---

# Agent: api-design

## Missão

API mal desenhada = dívida eterna porque clientes externos consomem.
Quebrar contrato pra arrumar custa caro depois. Este agente garante API
**nasce certa**: contrato versionado, idempotente, paginável, observável,
documentada como fonte de verdade.

## Quando rodar

- Módulo 4 (Rede & API) selecionado
- `api_detected: true` (Fase 02) ou tipo do projeto ∈ {api, saas, ecom, mobile}

## A. OpenAPI / JSON Schema como fonte de verdade

### Regra: contrato vem ANTES do código

```yaml
# openapi.yaml — versionado, é o "código mais importante" do projeto
openapi: 3.1.0
info:
  title: SalonPro API
  version: 2.3.0
  license: { name: MIT }
servers:
  - url: https://api.salonpro.com/v2
    description: Production
  - url: https://api-staging.salonpro.com/v2

paths:
  /appointments:
    get:
      operationId: listAppointments
      summary: Lista agendamentos com paginação cursor
      parameters:
        - { name: cursor, in: query, schema: { type: string } }
        - { name: limit,  in: query, schema: { type: integer, minimum: 1, maximum: 100, default: 20 } }
        - { name: status, in: query, schema: { type: string, enum: [scheduled,confirmed,completed,cancelled] } }
      responses:
        '200': { $ref: '#/components/responses/AppointmentList' }
        '400': { $ref: '#/components/responses/BadRequest' }
        '401': { $ref: '#/components/responses/Unauthorized' }
```

### Geração automática

- **Backend**: NestJS `@nestjs/swagger` decorators OU `ts-rest` / `tRPC` gera OpenAPI
- **Frontend client**: `openapi-typescript-codegen` gera SDK tipado
- **Validation**: AJV valida payload contra schema em runtime
- **Mock server**: Prism mockup do OpenAPI roda em dev
- **CI**: lint OpenAPI com Spectral, fail se breaking change não-versionado

```bash
# Spectral lint em CI
spectral lint openapi.yaml --ruleset spectral:oas
```

## B. Versionamento

| Estratégia | Como | Quando usar |
|---|---|---|
| **URL** (`/v1/`, `/v2/`) | Path prefix | Default — fácil pra cliente debugar |
| **Header** (`Accept: application/vnd.api.v2+json`) | Custom media type | API "pura" sem mudar URLs |
| **Query** (`?version=2`) | Param | Evitar — quebra cache |

**Regras:**
- Breaking change (remover campo, mudar tipo, mudar semântica) → **nova versão**
- Non-breaking (adicionar campo opcional, novo endpoint) → mesma versão
- Manter versão anterior por **mínimo 6 meses** após anúncio de deprecation
- Header `Sunset: Wed, 31 Dec 2026 23:59:59 GMT` + `Deprecation: true` em rotas antigas

## C. Idempotency keys (POST seguro)

Cliente envia header `Idempotency-Key: <uuid>`. Backend:
1. Olha tabela `idempotency_keys` por essa key
2. Se existe E payload bate → retorna resposta antiga
3. Se existe E payload divergente → 422 conflict
4. Se não existe → processa, salva (key, hash do request, response, status, expira em 24h)

```sql
CREATE TABLE idempotency_keys (
  key            TEXT PRIMARY KEY,
  request_hash   TEXT NOT NULL,    -- SHA256 do body
  response_body  JSONB NOT NULL,
  response_status SMALLINT NOT NULL,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at     TIMESTAMPTZ NOT NULL DEFAULT (now() + interval '24 hours')
);

CREATE INDEX idx_idem_expires ON idempotency_keys(expires_at);
```

Obrigatório em: pagamentos, criação de pedido, envio de mensagem, qualquer
POST que cause efeito externo.

## D. Paginação cursor (não offset em endpoints públicos)

### Por que cursor

- Offset cresce caro (skip lê N linhas)
- Offset duplica/perde items em datasets que mudam
- Cursor é estável: `cursor = base64(last_id + last_sort_value)`

```ts
// Request
GET /appointments?cursor=eyJpZCI6ImFiYyIsImF0IjoiMjAyNi0wNi0xNFQxMDowMCJ9&limit=20

// Response
{
  "data": [...],
  "meta": {
    "nextCursor": "eyJpZCI6Inh5eiIsImF0IjoiMjAyNi0wNi0xNFQxMjowMCJ9",
    "hasMore": true,
    "limit": 20
  }
}
```

Offset ainda OK em: admin/backoffice (precisa "página 47"), datasets pequenos
(<10k rows).

## E. Filtragem estruturada

### RSQL / FIQL (recomendado pra API pública)

```
GET /appointments?filter=status==scheduled;at=ge=2026-06-01;at=lt=2026-07-01
```

Lib: `@rsql/parser` (Node), `rsql-parser` (Python). Gera AST que vira WHERE.

### Alternativa simples (params planos)

```
GET /appointments?status=scheduled&at_gte=2026-06-01&at_lt=2026-07-01
```

Cobre 80% dos casos. Documentar conjunção (AND) e operadores (`_gte`, `_lt`, `_in`).

## F. Error format — RFC 7807 (Problem Details)

```json
{
  "type": "https://api.salonpro.com/errors/insufficient-balance",
  "title": "Saldo insuficiente",
  "status": 422,
  "detail": "Cliente não tem saldo suficiente para esta operação",
  "instance": "/v2/appointments/abc123",
  "errors": [
    { "field": "amount", "code": "INSUFFICIENT", "message": "Excede saldo R$ 50,00" }
  ],
  "requestId": "req_01HX2K9..."
}
```

Header obrigatório: `Content-Type: application/problem+json`.

Códigos padronizados (em config):
- 400: `VALIDATION_FAILED`, `MALFORMED_REQUEST`
- 401: `AUTH_REQUIRED`, `TOKEN_EXPIRED`, `TOKEN_INVALID`
- 403: `FORBIDDEN`, `INSUFFICIENT_ROLE`
- 404: `NOT_FOUND`, `RESOURCE_DELETED`
- 409: `CONFLICT`, `DUPLICATE_ENTRY`, `OPTIMISTIC_LOCK_FAILED`
- 422: `VALIDATION_ERROR` (com `errors[]` detalhando)
- 429: `RATE_LIMITED` (com header `Retry-After`)
- 500: `INTERNAL_ERROR` (NUNCA expor stack ao cliente)
- 503: `SERVICE_UNAVAILABLE`

## G. Status codes corretos

| Code | Uso |
|---|---|
| 200 | GET sucesso, PATCH sucesso |
| 201 | POST criou recurso (header `Location: /v2/x/<id>`) |
| 202 | Aceito, processamento assíncrono (incluir `id` do job) |
| 204 | DELETE sucesso (sem body) |
| 304 | ETag bate (`If-None-Match` matched) |
| 400 | Request malformada (JSON inválido, tipo errado) |
| 401 | Não autenticado |
| 403 | Autenticado mas sem permissão |
| 404 | Recurso não existe |
| 409 | Conflito (versão, duplicata) |
| 412 | Pre-condition failed (`If-Match` não bate) |
| 422 | Validação semântica falhou |
| 429 | Rate limit atingido |
| 500 | Erro do servidor (logar requestId, não expor) |
| 503 | Indisponível (manutenção, dependência fora) |

## H. ETags + conditional requests

```
# Read
GET /appointments/abc
< ETag: "v3-1718364920"

# Edit safe (avoid lost update)
PATCH /appointments/abc
> If-Match: "v3-1718364920"
< 412 Precondition Failed   # alguém editou no meio

# Cache
GET /appointments/abc
> If-None-Match: "v3-1718364920"
< 304 Not Modified           # sem body, banda zero
```

ETag = hash do content OU `version-updatedAt` (mais barato).

## I. Webhooks (outbound) — receita à prova de bala

### Signature HMAC

```
POST https://customer.com/webhook
Headers:
  Webhook-Id: msg_01HX...
  Webhook-Timestamp: 1718364920
  Webhook-Signature: v1,<base64(hmac_sha256(secret, id + "." + timestamp + "." + body))>

Body: { ... }
```

Cliente valida:
1. `now() - timestamp < 5min` (anti-replay)
2. HMAC bate
3. `msg_id` não foi processado antes (dedup, key armazenado 7 dias)

Lib: **Svix** (open source) cobre tudo.

### Retry strategy

- Backoff exponencial: 5s, 30s, 5min, 30min, 2h, 6h, 24h (8 tentativas)
- Dead Letter Queue após max retries
- Endpoint do cliente pode disable após N falhas consecutivas (notificar admin)

### Ordering

NÃO garantir ordering por default. Cliente que precisa ordenar usa
`occurred_at` no payload. Garantir ordering custa muito (fila serializada).

## J. Rate limit headers (cliente sabe onde está)

```
HTTP/1.1 200 OK
RateLimit-Limit: 100
RateLimit-Remaining: 87
RateLimit-Reset: 1718364920    # epoch
RateLimit-Policy: 100;w=60     # 100 reqs / 60s
```

Em 429:
```
HTTP/1.1 429 Too Many Requests
Retry-After: 23                # segundos
RateLimit-Reset: 1718364920
```

Padrão IETF draft `RateLimit-*` (lowercase em HTTP/2+).

## K. Contract testing (Pact)

```ts
// Consumer (frontend) — Pact define expectativa
const pact = new Pact({ consumer: 'web', provider: 'api' });

await pact.addInteraction({
  state: 'has 1 appointment',
  uponReceiving: 'a request to list appointments',
  withRequest: { method: 'GET', path: '/v2/appointments' },
  willRespondWith: {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
    body: { data: eachLike({ id: like('abc'), status: like('scheduled') }) }
  }
});
```

Provider (backend) verifica contratos antes de mergear: se quebrou contrato,
build fail.

## L. GraphQL (quando aplicável)

- **Persisted queries** (não aceitar query crua em produção — só hashes pré-registradas)
- **Depth limit** (~7) e **complexity limit** (ex: 1000 pontos)
- **N+1 via DataLoader** (Facebook pattern)
- **Field-level auth** (não só endpoint)
- **Rate limit por complexity points**, não por request count

Lib: `graphql-shield`, `graphql-armor`, `dataloader`.

## M. gRPC (quando aplicável)

Só pra comunicação interna entre serviços. Pra cliente público use REST/GraphQL.

## Output esperado em sec.html

```
┌─ API Design (Módulo 4) ──────────────────────────────────┐
│ OpenAPI fonte de verdade     : ✅ openapi.yaml versionado │
│ Spectral lint                : ✅ 0 warnings              │
│ Versionamento (path)         : ✅ /v2/                    │
│ Idempotency em POST críticos : ✅ 8/8 endpoints          │
│ Paginação cursor             : ✅ em 12 endpoints         │
│ Error format RFC 7807        : ✅                          │
│ Status codes corretos        : ✅ 47/47 endpoints         │
│ ETags em GET single          : ✅                          │
│ Rate limit headers           : ✅                          │
│ Webhook HMAC + dedup         : ✅ (Svix)                   │
│ Contract tests (Pact)        : ✅ FE↔BE green             │
│ Status                       : ✅ PRODUCTION-READY        │
└───────────────────────────────────────────────────────────┘
```

## Intelligence (⭐ v0.21) — endpoints intencionalmente diferentes

Nem todo POST precisa de idempotency key. Login é idempotent-by-design,
refresh-token também. Lê `.blindar/intelligence.yml`:

```yaml
api-design:
  idempotent_by_design:
    # POSTs onde idempotency é natural — não força header
    - "/auth/login"              # mesmo email+senha = mesmo resultado
    - "/auth/refresh"            # rotation interna gerencia
    - "/auth/logout"             # 200 sempre
    - "/auth/webauthn/options"
    - "/health/*"

  cursor_pagination_exempt:
    # Endpoints onde offset pagination é OK
    - "/admin/audit-log"         # admin precisa "página 47"
    - "/internal/*"              # tooling interno

  versioning_exempt:
    # Endpoints sem versionamento (estáveis pra sempre)
    - "/health/live"
    - "/health/ready"
    - "/.well-known/*"
    - "/robots.txt"

  rfc7807_exempt:
    # Endpoints que retornam formato custom por contrato externo
    - "/webhooks/stripe"         # Stripe espera 200 simples
    - "/webhooks/mercadopago"

  rate_limit_exempt:
    # Endpoints que NÃO precisam de rate limit
    - "/health/*"                # liveness não pode ser limitada
    - "/metrics"                 # Prometheus precisa rodar livre

  openapi_tags_to_ignore:
    # Tags que aparecem no OpenAPI mas não geram client
    - "internal"
    - "deprecated"

  inline_override_markers:
    no_idempotency: "@no-idempotency-needed"   # JSDoc tag
    no_versioning: "@stable-endpoint"
    custom_error: "@custom-error-format"
```

### Markers no controller

```ts
/**
 * @no-idempotency-needed -- login é idempotent-by-design
 * Mesmo email+senha sempre retorna mesma sessão se ainda válida.
 */
@Post('auth/login')
async login(@Body() dto: LoginDto) { ... }

/**
 * @stable-endpoint -- nunca versionar, faz parte do contrato bare-metal
 */
@Get('/health/live')
async live() { return { status: 'ok' }; }

/**
 * @custom-error-format -- Stripe webhook espera 200 + retry vs 4xx
 */
@Post('webhooks/stripe')
async stripeWebhook(@Body() event) { ... }
```

### Auto-detecção

- Endpoint com `@Get` que não muda estado → não exige idempotency
- Endpoint em path `/health/*`, `/metrics`, `/.well-known/*` → exempts
- Endpoint com retorno `text/plain` → não exige RFC 7807

### Profile por gateway de pagamento

Webhooks de payment seguem contratos diferentes:
- **Stripe**: espera 200 simples, retenta se 5xx
- **Mercado Pago**: similar, mas accepts 422
- **PagSeguro**: legacy SOAP em alguns endpoints

```yaml
api-design:
  webhook_profiles:
    stripe:
      success_response: 200
      retry_on: [500, 502, 503, 504]
      no_rfc7807: true
    mercadopago:
      success_response: [200, 422]
      retry_on: [500]
```

## Anti-padrões (CRIT)

- ❌ Documentação separada do código (deriva, vira mentira)
- ❌ Versionar quebrando sem aviso (cliente em produção)
- ❌ POST sem idempotency em pagamento
- ❌ Paginação por offset em endpoint público com >10k rows
- ❌ Erro `200 OK` com `{ success: false }` no body (use 4xx)
- ❌ `500` por bug do cliente (deveria ser 400/422)
- ❌ Stack trace no response body em produção
- ❌ Webhook sem signature (replay attack)
- ❌ GraphQL aceitando query crua em prod (deveria ser persisted)
- ❌ Rate limit silencioso (cliente não sabe quando vai voltar)
- ❌ Error message em uma língua só sem `requestId` pra debug
