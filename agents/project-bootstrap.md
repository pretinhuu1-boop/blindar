---
name: project-bootstrap
category: scaffolding
module: 14
priority: P1
description: |
  Cria projeto novo do ZERO. Pergunta tipo (SaaS/MVP/API/Mobile/Landing/
  Lib), escolhe stack baseada em respostas (Next.js 15+NestJS+Postgres,
  Vite+React, FastAPI, Expo, etc.), roda scaffolds oficiais
  (`create-next-app`, `nest new`), aplica padrões blindar desde o
  nascimento (.gitignore, .env.example, tsconfig strict, ESLint compartilhado,
  GitHub Actions CI, docker-compose, scripts iniciar.bat/sh, blindar.yml
  inicial, README com quickstart funcional, commit zero limpo). Não cria
  feature — cria o ALICERCE pra você começar codando.
---

# Agent: project-bootstrap

## Missão

Sempre que você começa projeto novo, perde 4-8h em coisa que deveria estar
pronta: ESLint config, GitHub Actions, docker-compose, README, prettier,
.env.example, husky, lint-staged, conventional commits. Este agente faz
tudo isso em 5min, na ordem certa, com padrões 2026 — e te entrega pronto
pra você focar na feature.

## Quando rodar

- Operador disse "projeto novo", "do zero", "scaffolding", "MVP"
- Diretório alvo está **vazio** (ou só tem `.git`)
- NÃO roda em projeto existente — pra evitar sobrescrever sem perceber

## A. Pergunta inicial (≤ 6 perguntas, ≤ 1min)

```
Vamos criar um projeto novo. 6 perguntas rápidas:

1. Nome do projeto: ___________ (será usado em package.json + folder + branding)

2. Tipo:
   1) SaaS (multi-tenant, dashboard, auth, billing)
   2) MVP / validação rápida (signup + 1 fluxo)
   3) E-commerce / Marketplace
   4) API pura (sem frontend)
   5) Landing page / Site institucional
   6) Mobile app (React Native/Expo)
   7) CLI / Lib (NPM publish)

3. Stack preferida (Enter pra sugestão):
   - Frontend: [Next.js 15 RSC] / Vite+React / Vue 3 / Astro
   - Backend:  [NestJS] / Fastify / Express / FastAPI (Python) / Hono (edge)
   - DB:       [Postgres + Prisma] / Drizzle / MySQL / MongoDB
   - Deploy:   [Vercel + Supabase] / Railway / AWS / Cloudflare / Self-hosted

4. Multi-tenant?
   1) Sim, multi-tenant (Master/Admin/Gerencial/Operacional — usa role-hierarchy)
   2) Não, single-tenant (usuário sozinho)

5. Sensibilidade dos dados (LGPD):
   A) ALTA (PII, financeiro, saúde) — já scaffolda módulo LGPD
   M) MÉDIA (login básico)
   B) BAIXA (público)

6. Idiomas:
   - pt-BR (default)
   - + en-US? (s/N)
   - + es-ES? (s/N)
   - + outros (digite)

Confirmar? (s/n)
```

Defaults entre `[colchetes]` aplicam se operador apertar Enter.

## B. Decisão automática de stack (baseada nas respostas)

| Tipo | Stack default |
|---|---|
| SaaS | Next.js 15 (App Router + RSC) + NestJS + Postgres + Prisma + Vercel + Supabase |
| MVP | Next.js 15 + Server Actions + Postgres + Vercel (mono-app, sem backend separado) |
| E-com | Next.js 15 + Stripe + Postgres + Algolia/Meilisearch + Vercel |
| API pura | NestJS + Postgres + Prisma + Swagger + Docker + Railway |
| Landing | Astro + Tailwind + Cloudflare Pages (estático, edge) |
| Mobile | Expo SDK 52 + EAS Build + Supabase + NestJS API |
| CLI/Lib | TypeScript + tsup + Changesets + GitHub Actions release |

Operador pode override em qualquer pergunta.

## C. Estrutura criada (exemplo SaaS multi-tenant)

```
salon-pro/
├── .github/
│   └── workflows/
│       ├── ci.yml                  ← lint + type-check + test + blindar dry-run
│       ├── deploy-staging.yml
│       └── deploy-prod.yml
├── .vscode/
│   ├── extensions.json             ← extensões recomendadas
│   └── settings.json
├── .husky/
│   ├── pre-commit                  ← lint-staged
│   └── commit-msg                  ← commitlint (conventional)
├── apps/
│   ├── web/                        ← Next.js 15 (frontend + Server Actions)
│   └── api/                        ← NestJS (API REST/GraphQL)
├── packages/
│   ├── shared/                     ← Zod schemas, types compartilhados
│   ├── ui/                         ← design system
│   └── config/                     ← eslint, tsconfig, tailwind
├── prisma/
│   ├── schema.prisma               ← com tenant_id + audit columns + RLS
│   └── seed.ts                     ← seed inicial (1 tenant, 4 users por role)
├── scripts/
│   ├── iniciar.bat                 ← Windows
│   ├── iniciar.sh                  ← Linux/macOS
│   └── reset-db.sh
├── docker-compose.yml              ← Postgres + Redis local
├── .env.example                    ← TODAS variáveis documentadas
├── .gitignore                      ← Node, env, .blindar local
├── .nvmrc                          ← Node version
├── .editorconfig
├── package.json                    ← scripts: dev, build, test, lint, blindar
├── pnpm-workspace.yaml             ← monorepo config
├── turbo.json                      ← Turborepo pipeline
├── README.md                       ← quickstart < 5min funcional
├── CONTRIBUTING.md
├── CHANGELOG.md                    ← inicia vazio com changesets
├── LICENSE                         ← (escolhido na pergunta)
└── .blindar/
    └── config.yml                  ← já configurado conforme respostas
```

## D. Conteúdo de arquivos críticos gerados

### .env.example (com TODAS variáveis necessárias documentadas)

```bash
# ──────────── App ────────────
NODE_ENV=development
PORT=3000
NEXT_PUBLIC_BRAND_NAME="Salon Pro"
NEXT_PUBLIC_APP_URL=http://localhost:3000

# ──────────── Database (Postgres) ────────────
# Local: docker compose up -d  →  postgres://postgres:postgres@localhost:5432/salon_dev
# Prod:  pegue em supabase.com → Settings → Database
DATABASE_URL=
DIRECT_URL=                          # Prisma migrations (sem pooler)

# ──────────── Auth ────────────
# Gere com: openssl rand -base64 32
JWT_SECRET=
REFRESH_TOKEN_SECRET=
WEBAUTHN_RPID=localhost
WEBAUTHN_ORIGIN=http://localhost:3000

# ──────────── Stripe (se cobra) ────────────
STRIPE_SECRET_KEY=
STRIPE_PUBLIC_KEY=
STRIPE_WEBHOOK_SECRET=

# ──────────── WhatsApp / Evolution API (se aplicável) ────────────
EVOLUTION_API_URL=
EVOLUTION_API_KEY=

# (... e assim por diante, agrupado por serviço)
```

### docker-compose.yml

```yaml
services:
  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: salon_dev
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
    ports: ["5432:5432"]
    volumes: [postgres_data:/var/lib/postgresql/data]
    healthcheck:
      test: ["CMD", "pg_isready", "-U", "postgres"]
      interval: 5s

  redis:
    image: redis:7-alpine
    ports: ["6379:6379"]
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]

  pgadmin:
    image: dpage/pgadmin4
    environment:
      PGADMIN_DEFAULT_EMAIL: admin@local
      PGADMIN_DEFAULT_PASSWORD: admin
    ports: ["5050:80"]
    profiles: [tools]                # docker compose --profile tools up

volumes:
  postgres_data:
```

### scripts/iniciar.bat (Windows)

```bat
@echo off
echo === Iniciando Salon Pro ===
where docker >nul 2>&1 || (echo Docker nao encontrado. Instale: https://docker.com & pause & exit)
docker compose up -d
if not exist node_modules (
  echo === Instalando dependencias ===
  call pnpm install
)
if not exist .env (
  echo === Copiando .env.example pra .env ===
  copy .env.example .env
  echo ATENCAO: edite .env com seus valores antes de continuar
  pause
)
call pnpm db:migrate
call pnpm dev
```

### scripts/iniciar.sh (Linux/macOS)

```bash
#!/usr/bin/env bash
set -e
echo "=== Iniciando Salon Pro ==="
command -v docker >/dev/null || { echo "Docker nao encontrado"; exit 1; }
docker compose up -d
[ ! -d node_modules ] && pnpm install
[ ! -f .env ] && cp .env.example .env && echo "ATENCAO: edite .env" && exit 0
pnpm db:migrate
pnpm dev
```

### package.json (raiz monorepo)

```json
{
  "name": "salon-pro",
  "private": true,
  "engines": { "node": ">=20.18.0", "pnpm": ">=9" },
  "scripts": {
    "dev":        "turbo run dev",
    "build":      "turbo run build",
    "test":       "turbo run test",
    "lint":       "turbo run lint",
    "type-check": "turbo run type-check",
    "db:migrate": "pnpm --filter @salon/api prisma migrate dev",
    "db:seed":    "pnpm --filter @salon/api prisma db seed",
    "blindar":    "blindar",
    "release":    "changeset publish"
  },
  "devDependencies": {
    "turbo": "^2",
    "@changesets/cli": "^2",
    "husky": "^9",
    "lint-staged": "^15",
    "@commitlint/cli": "^19",
    "@commitlint/config-conventional": "^19"
  }
}
```

### .github/workflows/ci.yml

```yaml
name: CI
on: [push, pull_request]
concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true
jobs:
  ci:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: 20, cache: pnpm }
      - run: pnpm install --frozen-lockfile
      - run: pnpm lint
      - run: pnpm type-check
      - run: pnpm test
      - run: pnpm build

  blindar-dry-run:
    runs-on: ubuntu-latest
    if: github.event_name == 'pull_request'
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: 20, cache: pnpm }
      - run: pnpm install --frozen-lockfile
      - run: npx blindar --dry-run --headless
```

### .gitignore

```gitignore
# Dependencies
node_modules/
.pnp.*

# Build outputs
dist/
.next/
out/
build/

# Environment (CRIT — nunca commitar)
.env
.env.local
.env.*.local

# IDE
.vscode/*
!.vscode/extensions.json
!.vscode/settings.json
.idea/

# OS
.DS_Store
Thumbs.db

# Logs
*.log
npm-debug.log*
pnpm-debug.log*

# Testing
coverage/
.nyc_output/

# blindar (local state)
.blindar/state.json
.blindar/discovery/
.blindar/checkpoints/

# Uploads / user data (NUNCA commitar)
uploads/
data/
```

### README.md (quickstart < 5min, testado)

```markdown
# Salon Pro

> Sistema de gestão para salões de beleza — agenda, clientes, financeiro, WhatsApp.

[![CI](https://github.com/owner/repo/actions/workflows/ci.yml/badge.svg)](...)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

## Quickstart (5 minutos)

### Pré-requisitos
- Node.js >= 20.18
- pnpm >= 9 (`npm i -g pnpm`)
- Docker Desktop

### Comandos

```bash
git clone <repo>
cd salon-pro
./scripts/iniciar.sh          # Linux/macOS
# OU
scripts\iniciar.bat            # Windows
```

Abre em http://localhost:3000

Login de teste:
- master@local / `@Teste123`
- admin@local / `@Teste123`

## Stack

| Camada | Tecnologia |
|---|---|
| Frontend | Next.js 15 (App Router + RSC) |
| Backend | NestJS 11 |
| Banco | PostgreSQL 16 + Prisma |
| Auth | WebAuthn + JWT + refresh rotation |
| Deploy | Vercel + Supabase |

## Estrutura

(ver árvore em [docs/architecture.md](docs/architecture.md))

## Próximos passos

- [ ] Editar `.env` com suas chaves
- [ ] Rodar `pnpm blindar` pra validar produção-readiness
- [ ] Ler `CONTRIBUTING.md`

## Licença

MIT
```

### .blindar/config.yml (já configurado)

```yaml
schema: blindar/config@v0.18
mode: auto
selected_modules: [1, 2, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]  # todos
project_type: saas
data_sensitivity: high
rigor: production
target_framework: lgpd
ui_detected: true
db_detected: true
branch: main
launcher_completed_at: ""
```

## E. Seed inicial (`prisma/seed.ts`)

```typescript
import { PrismaClient, Role } from '@prisma/client';
import argon2 from 'argon2';
const prisma = new PrismaClient();

async function main() {
  const tenant = await prisma.tenant.create({
    data: { name: 'Beleza Real (Demo)', slug: 'beleza-real' }
  });
  const passwordHash = await argon2.hash('@Teste123', { type: argon2.argon2id });

  await prisma.user.createMany({
    data: [
      { email: 'master@local',  role: Role.MASTER,       passwordHash, tenantId: null },
      { email: 'admin@local',   role: Role.ADMIN,        passwordHash, tenantId: tenant.id },
      { email: 'gerente@local', role: Role.GERENCIAL,    passwordHash, tenantId: tenant.id },
      { email: 'op@local',      role: Role.OPERACIONAL,  passwordHash, tenantId: tenant.id }
    ]
  });

  console.log('✓ Seed: 1 tenant, 4 users (todas roles)');
}

main().catch(console.error).finally(() => prisma.$disconnect());
```

## F. Commit zero

Após scaffolding:

```bash
git init
git add .
git commit -m "chore: initial scaffold via blindar project-bootstrap

Stack: Next.js 15 + NestJS + Postgres + Prisma
Type: SaaS multi-tenant
Roles: MASTER/ADMIN/GERENCIAL/OPERACIONAL
Sensitivity: HIGH (LGPD ON)
Languages: pt-BR

Defaults aplicados:
- ESLint + Prettier + commitlint + husky
- GitHub Actions CI (lint + test + build + blindar dry-run)
- Docker compose com Postgres+Redis
- Scripts iniciar.bat / iniciar.sh
- Prisma schema com tenant_id + audit columns + RLS
- Seed com 4 users de teste por role

Próximo: edite .env, rode ./scripts/iniciar.sh
"
```

Branch principal: `main`. Operador pode mudar.

## G. Decisões aplicadas SEM perguntar (padrões blindar)

- TypeScript **strict** desde o dia 1 (`strict: true, noUncheckedIndexedAccess: true`)
- ESLint + Prettier + import sorting + tailwind class sorting
- Conventional commits via commitlint
- Husky pré-commit (lint-staged) + pre-push (tests)
- Node version pinada em `.nvmrc`
- pnpm como package manager (workspaces nativos, mais rápido)
- Engines no package.json
- License MIT default (perguntar se quer outra)
- README com badges de CI/coverage/license
- Tabela compatibilidade browser/SO

## H. NÃO faz (escopo)

- ❌ Implementar feature de negócio (esse é trabalho do dev)
- ❌ Configurar provedores externos (Stripe key, etc.) — só template
- ❌ Comprar domínio
- ❌ Decidir branding/cores específicos (operator define)
- ❌ Sobrescrever projeto existente — exige confirmação dupla

## I. Greps de validação (após scaffolding)

```bash
# Tudo presente?
test -f package.json
test -f .env.example
test -f .gitignore
test -f docker-compose.yml
test -f README.md
test -f .blindar/config.yml
test -d .github/workflows
test -d scripts

# CI roda?
gh workflow list 2>/dev/null || echo "(gh not configured)"

# Lint OK?
pnpm lint --quiet || echo "FAIL: lint"

# Build OK em scaffold vazio?
pnpm build || echo "FAIL: build"

# Commit zero criado?
git log -1 --oneline | grep -q "initial scaffold" || echo "FAIL: commit"
```

## J. Output esperado em sec.html

```
┌─ Project Bootstrap (Módulo 14) ──────────────────────────┐
│ Tipo escolhido                : SaaS multi-tenant         │
│ Stack: Next.js 15 + NestJS + Postgres                     │
│ Estrutura monorepo (Turborepo): ✅                         │
│ Husky + commitlint            : ✅                         │
│ GitHub Actions CI             : ✅ (4 workflows)          │
│ Docker compose + healthchecks : ✅                         │
│ Scripts iniciar.bat/sh        : ✅                         │
│ Prisma schema com tenant_id   : ✅ + audit + RLS          │
│ Seed: 4 users por role        : ✅                         │
│ README quickstart < 5min      : ✅ testado                 │
│ .env.example documentado      : ✅ 23 variáveis            │
│ .blindar/config.yml inicial   : ✅                         │
│ Licença                       : MIT                        │
│ Commit zero                   : ✅                         │
│ Status                        : ✅ READY TO CODE          │
└───────────────────────────────────────────────────────────┘
```

## K. Anti-padrões

- ❌ Scaffold em pasta não-vazia (overwrite silencioso)
- ❌ Stack com hype não-comprovado (escolher só o que tem trilha real)
- ❌ Esquecer engines no package.json (dev novo erra Node version)
- ❌ Commitar `.env` ou secrets reais no scaffold
- ❌ README com quickstart que não funciona (testar antes!)
- ❌ Seed com dados sem aviso "(Demo)" (some mistakes em prod)
- ❌ Default sem `.editorconfig` (quebra a regra do projeto)
- ❌ ESLint sem `--max-warnings 0` (warnings vira ruído)
- ❌ Sem `.nvmrc` (cada dev usa versão diferente)
- ❌ TypeScript com `strict: false` (vai virar dívida)
- ❌ Não rodar `pnpm install` ao final (operador pega projeto sem deps)
- ❌ Não commitar (operador perde estado se zerar)
