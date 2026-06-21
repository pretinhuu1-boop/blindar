---
name: documentation-live
category: dx
module: 14
priority: P2
description: |
  Documentação que MORRE com o código (gerada/sincronizada, não escrita
  à mão e esquecida). Cobre: API docs interactive (Redoc/Scalar do
  OpenAPI), Storybook pra componentes UI, ADRs (Architecture Decision
  Records) versionados, README com badges + quickstart < 5min, CHANGELOG
  semver, code comments só onde "porquê" não é óbvio, diagramas
  versionáveis (Mermaid em md).
---

# Agent: documentation-live

## Missão

Doc separada do código apodrece em semanas. Doc gerada do código vive.
Este agente prescreve **fontes únicas de verdade** que geram doc
automaticamente, e ADRs pra decisões que não estão no código.

## Quando rodar

- Módulo 14 selecionado
- Time > 1 dev OU código será mantido > 6 meses
- Operador pediu "docs", "onboarding de dev", "ADR"

## A. README — primeira impressão

### Estrutura mínima (~100 linhas)

```markdown
# Salon Pro

> Software de gestão para salões — agenda, clientes, financeiro, WhatsApp.

[![CI](badge)] [![Coverage](badge)] [![Version](badge)] [![License](badge)]

## Quickstart (≤ 5min)

```bash
git clone ...
cd salon-pro
cp .env.example .env
npm install
docker compose up -d  # PostgreSQL + Redis
npm run db:migrate
npm run dev
# → http://localhost:3000
```

## Stack

- Frontend: Next.js 15 + RSC
- Backend: NestJS + Prisma
- DB: PostgreSQL 16
- Auth: WebAuthn + JWT
- Deploy: Vercel + Supabase

## Estrutura

```
salon-pro/
├── apps/web/         Next.js app
├── apps/api/         NestJS API
├── packages/shared/  Schemas Zod + types
└── packages/ui/      Design system
```

## Comandos

| | |
|---|---|
| `npm run dev` | Inicia tudo (web + api) |
| `npm test` | Roda suite |
| `npm run lint` | ESLint + Prettier |
| `npm run blindar` | Audit de produção |

## Docs

- [API interativa](/docs/api)
- [Storybook](/storybook)
- [ADRs](docs/adr/)
- [Contributing](CONTRIBUTING.md)

## Licença
MIT
```

### Regras

- Quickstart **deve funcionar** num dev novo em < 5min (testado mensal)
- Badges atualizam automático (CI, coverage, deps)
- Links pra docs mais profundas (não tudo no README)

## B. API docs interativa (Redoc / Scalar / Swagger UI)

### Source of truth: OpenAPI (já em `api-design.md`)

```ts
// Servir UI interativa
import { ScalarApiReference } from '@scalar/express-api-reference';

app.use('/docs/api', ScalarApiReference({
  spec: { url: '/openapi.json' },
  configuration: {
    theme: 'purple',
    showSidebar: true,
    hideDownloadButton: false
  }
}));
```

### Recursos chave

- **Try it out** (request real do browser)
- **Code samples** em 10+ linguagens
- **Authentication** (cole token, persiste)
- **Versioning** (v1 / v2)

Alternativas:
- **Redoc** (read-only, mais bonito)
- **Swagger UI** (clássico, padrão)
- **Scalar** (moderno, recomendado 2026)
- **Stoplight** (hosted)

## C. Storybook (componentes UI)

```bash
npx storybook@latest init
```

### Stories obrigatórias por componente

```tsx
// Button.stories.tsx
export default { component: Button, title: 'UI/Button' };

export const Primary = { args: { children: 'Salvar', variant: 'primary' } };
export const Secondary = { args: { children: 'Cancelar', variant: 'secondary' } };
export const Loading = { args: { children: 'Salvando…', loading: true } };
export const Disabled = { args: { children: 'Não disponível', disabled: true } };
export const WithIcon = { args: { children: 'Adicionar', icon: <PlusIcon /> } };

// Test visual com Chromatic / Percy
```

### Addons valiosos

- **a11y** — testa WCAG no preview
- **interactions** — testa fluxos com play function
- **controls** — props edit ao vivo
- **viewport** — preview em mobile/tablet/desktop
- **dark mode** — toggle de tema

### Chromatic visual regression

Mudou cor de Button? Pixel diff detecta. Build vermelho se não aprovado
no review visual.

## D. ADRs (Architecture Decision Records)

Decisões importantes ficam em **markdown versionado** — não em DM/Slack.

```markdown
# ADR 001: Usar PostgreSQL como DB principal

Status: accepted
Date: 2026-01-15
Authors: @maykonbts

## Contexto

Precisamos escolher DB primário. Opções consideradas: PostgreSQL,
MySQL, MongoDB.

## Decisão

PostgreSQL 16.

## Razão

1. JSONB cobre 80% dos casos "schemaless" sem mudar de DB
2. RLS resolve multi-tenant nativamente
3. Time já conhece (curva 0)
4. Supabase/Neon oferecem managed barato
5. Extensões (pg_uuidv7, pgvector) cobrem casos futuros

## Consequências

- Custo: managed Supabase ~$25/mês inicial
- Risco: scaling write requer particionamento (Citus se passar de 100M rows)
- Migração: refazer queries quando trocar (improvável < 5 anos)

## Alternativas rejeitadas

- **MongoDB**: schemaless puro vira dívida (tipos não consistentes)
- **MySQL**: sem RLS nativo, JSONB pior, FK até MySQL 8 não era confiável
```

### Estrutura

```
docs/adr/
├── 0001-postgresql.md
├── 0002-nestjs-vs-fastify.md
├── 0003-webauthn-passkeys.md
├── 0004-multi-tenant-strategy.md
└── 0005-feature-flag-storage.md
```

Status: `proposed` → `accepted` / `rejected` / `superseded by 00X`.

NUNCA editar ADR aceita. Cria nova que substitui.

## E. CHANGELOG semver

```markdown
# Changelog

## [2.3.0] — 2026-06-14

### Adicionou
- Integração WhatsApp via Evolution API (#42)
- Onboarding tour (#48)

### Mudou
- Login agora suporta WebAuthn (#45)

### Removeu
- Suporte a IE11 (deprecated em 2.0)

### Fixou
- Race condition em refresh token (#51)

### Segurança
- Atualiza axios 1.6 → 1.7 (CVE-2024-XXXX)
```

Gerar automático com **changesets** (`@changesets/cli`).

## F. Code comments — só "porquê"

```ts
// ❌ COMENTA O QUÊ (óbvio)
// Soma a e b
function sum(a, b) { return a + b; }

// ✅ COMENTA O PORQUÊ (não-óbvio)
function calculateInterest(principal, days) {
  // Usa base 360, não 365 — convenção bancária brasileira
  // (regulamento BCB 4.595/64 art. 17)
  return principal * RATE * days / 360;
}
```

### Quando comentar

- Workaround pra bug específico (link pra issue)
- Constraint regulatória/legal
- Performance hack não-óbvio
- Decisão que parece errada mas é certa (com motivo)

### Quando NÃO comentar

- Repetir o nome da função
- Função que já é clara
- "TODO" que nunca será feito (cria issue)

## G. JSDoc / TSDoc em API pública (libs)

```ts
/**
 * Cria appointment respeitando regras de tenant + scope do usuário.
 *
 * @param dto - dados do appointment
 * @param userId - usuário que está criando (escopo aplicado)
 * @throws {NotFoundError} se cliente não existe ou não pertence ao tenant
 * @throws {ConflictError} se horário já ocupado
 *
 * @example
 * await createAppointment({ clientId, scheduledAt }, userId);
 */
export async function createAppointment(dto: CreateDto, userId: string) { /* ... */ }
```

### Geração de docs

- **TypeDoc** → HTML estático
- **API Extractor** (Microsoft) → relatórios + .d.ts versionados

## H. Diagramas (Mermaid em markdown)

```markdown
## Fluxo de autenticação

```mermaid
sequenceDiagram
    actor U as User
    participant FE as Frontend
    participant BE as Backend
    participant DB as Postgres

    U->>FE: Email + senha
    FE->>BE: POST /auth/login
    BE->>DB: Verifica hash Argon2id
    DB-->>BE: User OK
    BE->>BE: Gera JWT + Refresh
    BE-->>FE: Tokens + user
    FE->>FE: setSession()
\`\`\`
```

GitHub renderiza nativo. Mudou fluxo? Edita o markdown.

Outras: arquitetura (`graph TD`), Gantt, ER diagrams.

## I. Runbooks de operação

Já cobertos em `backup-recovery`, `compliance-lgpd-br`. Resumo:

```
docs/runbooks/
├── incident-response.md     ← processo de incidente
├── key-rotation.md          ← rotação trimestral
├── supply-chain.md          ← reagir a CVE em dep
├── backup-restore.md        ← drill mensal
├── breach-notification.md   ← LGPD 3 dias úteis
└── on-call.md               ← rotação + escalation
```

Cada runbook: **objetivo, gatilho, passos, SLA, owner**.

## J. Onboarding doc pra novo dev

```markdown
# Onboarding — primeiro dia

## Acessos
- [ ] GitHub (peça invite ao tech lead)
- [ ] AWS console (read-only inicial)
- [ ] Supabase
- [ ] Slack #salon-pro-eng

## Setup local
1. Siga o [README#quickstart](README.md#quickstart)
2. Rode `npm run dev` — deve abrir em localhost:3000
3. Login com `dev@local` / `dev123` (seed)
4. Crie um appointment de teste

## Próximas tarefas
- Leia [ADR 001-005](docs/adr/) (entende decisões)
- Faça primeiro PR: fix um issue marcado `good-first-issue`
- 1:1 com tech lead na segunda

## Quando travar
- Slack #salon-pro-eng
- Email tech lead
- Documento [Troubleshooting](docs/troubleshooting.md)
```

## K. Greps obrigatórios

```bash
# README sem badges
rg -L "\!\[.*\]\(" README.md

# Sem .env.example
ls .env.example 2>/dev/null || echo "⚠ .env.example faltando"

# ADRs como issue de Slack/Notion (não no repo)
ls docs/adr/ 2>/dev/null || echo "⚠ Sem ADRs versionados"

# README sem quickstart funcional
rg -L "(npm|yarn|pnpm) (install|i)" README.md

# Storybook configurado mas sem stories
[ -d .storybook ] && [ $(find . -name "*.stories.*" -not -path "./node_modules/*" | wc -l) -eq 0 ] && echo "⚠ Storybook vazio"
```

## Output esperado em sec.html

```
┌─ Documentation Live (Módulo 14) ─────────────────────────┐
│ README com quickstart < 5min  : ✅ testado mensal         │
│ .env.example sincronizado     : ✅                         │
│ API docs (Scalar)             : ✅ /docs/api              │
│ Storybook                     : ✅ 47 stories             │
│ Chromatic visual regression   : ✅                         │
│ ADRs versionados              : 8 decisões                │
│ CHANGELOG semver              : ✅ changesets             │
│ Diagramas Mermaid             : 5 (arch, auth, db ER...)  │
│ Runbooks operacionais         : 6/6                       │
│ Onboarding doc                : ✅                         │
│ Code comments (só "porquê")   : ✅ greps clean            │
│ TypeDoc gerado em CI          : ✅                         │
│ Status                        : ✅ DOCUMENTED             │
└───────────────────────────────────────────────────────────┘
```

## Anti-padrões

- ❌ README desatualizado (quickstart não funciona mais)
- ❌ Doc em Notion/Confluence sem versionar (apodrece)
- ❌ Decisão importante no Slack DM (perde)
- ❌ ADR editada depois de aceita (cria nova superseding)
- ❌ Comentário que repete o nome da função
- ❌ TODO eterno no código (cria issue)
- ❌ Storybook configurado mas vazio (overhead sem ganho)
- ❌ API doc desatualizada (gera do código!)
- ❌ Diagrama em PNG (não versionável — use Mermaid)
- ❌ CHANGELOG escrito à mão (use changesets)
- ❌ Runbook teórico ("em caso de incidente, faça X") sem drill prático
- ❌ Onboarding doc que assume conhecimento prévio do código
