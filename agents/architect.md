---
name: architect
category: dx
module: 14
priority: P1
description: |
  Cuida da estrutura: pastas, arquivos, naming, fronteiras entre módulos,
  detecção de ciclos, dead code, arquivos gigantes, "utils.ts" canivete
  suíço, importações cruzadas que não deveriam existir. Aplica blueprint
  do mercado conforme tipo do projeto (Next.js, NestJS, monorepo, etc.).
  Mantém a organização saudável conforme o projeto cresce. Refator
  gradual quando estrutura sai do trilho — nunca big-bang.
---

# Agent: architect

## Missão

Projeto começa organizado, vira bagunça em 6 meses. Padrão: `utils.ts`
com 800 linhas, components importando de pages, dependência circular
entre módulos, 10 versões diferentes da mesma função em pastas
diferentes. Custo: novo dev demora semana pra entender, refactor vira
medo. Este agente **mantém a casa organizada** ao longo do tempo.

## Quando rodar

- Módulo 14 selecionado (sempre que rigor ≥ produção)
- Tipo do projeto ∈ {saas, ecom, api, mobile, monorepo}
- Operador pediu "organizar", "arquitetura", "refator"

## A. Detecção de tipo de projeto + blueprint

```bash
# Detect stack
if [ -f next.config.js ] || [ -f next.config.ts ]; then echo "nextjs"; fi
if [ -f nest-cli.json ]; then echo "nestjs"; fi
if [ -f turbo.json ] || [ -f pnpm-workspace.yaml ]; then echo "monorepo"; fi
if [ -f vite.config.ts ] && grep -q "react" package.json; then echo "react-spa"; fi
if [ -f tsconfig.json ] && grep -q "@nestjs/cli" package.json; then echo "nestjs"; fi
if [ -f pyproject.toml ] && grep -q "fastapi" pyproject.toml; then echo "fastapi"; fi
```

Cada stack tem **blueprint próprio** (próxima seção).

## B. Blueprints por stack (estrutura recomendada 2026)

### B.1 Next.js 15 (App Router, RSC default)

```
projeto/
├── app/                          ← roteamento (Server Components default)
│   ├── (marketing)/              ← grupos de rota
│   │   ├── layout.tsx
│   │   └── page.tsx
│   ├── (app)/                    ← área autenticada
│   │   ├── layout.tsx
│   │   ├── dashboard/page.tsx
│   │   └── settings/page.tsx
│   ├── api/                      ← route handlers
│   │   └── webhooks/stripe/route.ts
│   └── layout.tsx                ← root layout
│
├── components/
│   ├── ui/                       ← primitivos (Button, Input — Radix/shadcn)
│   ├── forms/                    ← compostos por feature
│   └── layout/                   ← Header, Sidebar
│
├── lib/                          ← lógica reutilizável SEM UI
│   ├── auth/
│   ├── db/                       ← Prisma client + queries
│   ├── stripe/
│   └── utils/                    ← helpers PUROS (nunca 'use client')
│
├── hooks/                        ← React hooks compartilhados
├── server/                       ← lógica server-only (server actions)
├── types/                        ← types compartilhados (Zod schemas)
├── public/
├── locales/                      ← i18n
└── tests/
```

**Regras:**
- `app/` NUNCA importa de `tests/`
- `components/` NÃO importa de `app/` (componente é genérico)
- `lib/utils/` NUNCA tem `'use client'` (helpers puros)
- Server Actions em `server/actions/<feature>.ts`
- Componente client tem `.client.tsx` opcional pra ficar explícito

### B.2 NestJS (DDD-light, modules por domínio)

```
src/
├── modules/                      ← um módulo por domínio
│   ├── auth/
│   │   ├── auth.controller.ts
│   │   ├── auth.service.ts
│   │   ├── auth.module.ts
│   │   ├── dto/
│   │   ├── guards/
│   │   ├── decorators/
│   │   └── strategies/
│   ├── appointments/
│   │   ├── appointments.controller.ts
│   │   ├── appointments.service.ts
│   │   ├── appointments.module.ts
│   │   ├── domain/               ← entidades + value objects
│   │   ├── infrastructure/       ← Prisma repos
│   │   └── dto/
│   └── ...
├── common/                       ← cross-cutting (filters, pipes, interceptors)
├── prisma/
├── config/
└── main.ts
```

**Regras:**
- Cada module é AUTOCONTIDO (pode ser extraído pra microsserviço)
- `modules/A` NÃO importa de `modules/B` direto — via interface/event
- `common/` só pra cross-cutting (NUNCA business logic)
- Controller fino, service grosso, repos finos

### B.3 Monorepo (Turborepo / Nx / pnpm)

```
projeto/
├── apps/
│   ├── web/                      ← Next.js
│   ├── api/                      ← NestJS
│   ├── mobile/                   ← Expo
│   └── docs/                     ← Nextra/Mintlify
├── packages/
│   ├── ui/                       ← design system (Storybook aqui)
│   ├── shared/                   ← Zod schemas + types compartilhados
│   ├── config/                   ← eslint/tsconfig/tailwind compartilhado
│   └── api-sdk/                  ← cliente OpenAPI gerado
├── tooling/
│   └── scripts/                  ← build, deploy, blindar
├── turbo.json / nx.json
├── pnpm-workspace.yaml
└── package.json
```

**Regras:**
- `apps/A` NUNCA importa de `apps/B` (só de `packages/`)
- `packages/` versionado via changesets
- Dependência compartilhada na raiz, específica no package
- Conventional commits com **scope obrigatório**: `feat(web):`, `fix(api):`

### B.4 React SPA (Vite)

```
src/
├── app/                          ← App.tsx, router, providers
├── pages/                        ← uma pasta por rota top-level
├── components/
├── features/                     ← lógica feature-based
│   └── appointments/
│       ├── api.ts
│       ├── hooks.ts
│       ├── components/
│       └── types.ts
├── lib/
├── hooks/
└── types/
```

### B.5 FastAPI / Python

```
src/
├── domain/                       ← entidades, value objects, regras
├── infrastructure/               ← repos SQLAlchemy, externos
├── application/                  ← use cases / services
├── presentation/                 ← FastAPI routers, schemas Pydantic
├── core/                         ← config, security, deps
└── main.py
```

## C. Naming conventions (não-negociáveis)

| Tipo | Convention | Exemplo |
|---|---|---|
| Arquivo | `kebab-case` | `user-profile.ts` |
| React Component | `PascalCase` arquivo + componente | `UserProfile.tsx` |
| Hook | `useCamelCase.ts` | `useAuth.ts` |
| Util/lib | `kebab-case` ou `camelCase.ts` | `format-date.ts` |
| Constants file | `UPPER_SNAKE.ts` no nome do export | `const MAX_RETRIES = 5` |
| Pasta | `kebab-case` | `user-profile/` |
| Test | adjacent ou `__tests__/` | `UserProfile.test.tsx` |
| Story | adjacent | `Button.stories.tsx` |
| Type-only file | `.types.ts` | `appointment.types.ts` |

**Consistência conta mais que escolha** — escolhido `kebab` no projeto?
mantém em 100%. Misturar é o pior.

## D. Boundaries (fronteiras entre módulos)

### Tool: `dependency-cruiser`

```js
// .dependency-cruiser.cjs
module.exports = {
  forbidden: [
    {
      name: 'no-cross-feature-import',
      severity: 'error',
      from: { path: '^src/features/([^/]+)/' },
      to:   { path: '^src/features/(?!\\1)/' }
    },
    {
      name: 'no-import-app-from-components',
      severity: 'error',
      from: { path: '^components/' },
      to:   { path: '^app/' }
    },
    {
      name: 'no-circular',
      severity: 'error',
      from: {},
      to: { circular: true }
    },
    {
      name: 'no-test-import-from-prod',
      severity: 'error',
      from: { path: '\\.test\\.' },
      to:   { path: '^src/(?!test)' }
    }
  ]
};
```

Roda em CI: `npx depcruise src --validate`. Falha = block merge.

### Alternativa: ESLint plugin

- `eslint-plugin-boundaries` (declarativo)
- `eslint-plugin-import` + `no-restricted-paths`
- Em monorepo Nx: `@nx/enforce-module-boundaries`

### Aliases no tsconfig (path mapping)

```json
{
  "compilerOptions": {
    "baseUrl": ".",
    "paths": {
      "@/lib/*": ["src/lib/*"],
      "@/components/*": ["src/components/*"],
      "@/features/*": ["src/features/*"],
      "@/hooks/*": ["src/hooks/*"]
    }
  }
}
```

Elimina `../../../../lib/utils`. Refactor de pasta não quebra imports.

## E. File size limits (smell detection)

| Tipo | Limite | Acima disso |
|---|---|---|
| Componente React | 300 LOC | Quebrar (extrair sub-components/hooks) |
| Hook | 100 LOC | Extrair lógica pra lib pura |
| Util/lib | 200 LOC | Dividir por subtópico |
| Service / repo | 400 LOC | Separar por agregado/use case |
| Page (Next.js) | 200 LOC | Pode estar fazendo trabalho de feature — extrair |
| Test file | 500 LOC | Dividir por sub-cenário |
| **`utils.ts` genérico** | **❌ PROIBIDO** | Sempre nomear por domínio: `date-utils.ts`, `string-utils.ts`, `currency-utils.ts` |

### Grep

```bash
# Arquivos > 400 LOC
find src -type f \( -name '*.ts' -o -name '*.tsx' \) | xargs wc -l | sort -rn | head -20

# utils.ts genérico (CRIT)
find src -name 'utils.ts' -o -name 'helpers.ts' -o -name 'common.ts' 2>/dev/null

# index.ts gigante (barril abusado)
find src -name 'index.ts' | xargs -I {} sh -c 'lc=$(wc -l < {}); [ $lc -gt 50 ] && echo "{}: $lc lines"'
```

## F. Feature-based vs Layer-based — quando usar

| Layer-based (`/components`, `/hooks`, `/lib`) | Feature-based (`/features/appointments/...`) |
|---|---|
| Bom pra projetos pequenos (<20 features) | Bom pra projetos grandes (>20 features) |
| Fácil de começar | Reduz cognitive load |
| Pode virar bagunça em escala | Cada feature é autocontida |
| Components reusáveis aparecem cedo | Components reusáveis vão pra `/components/ui` |

**Híbrido (recomendado 2026):**

```
src/
├── components/ui/        ← primitivos compartilhados (Button, Input)
├── lib/                  ← utilities compartilhadas (puras)
├── hooks/                ← hooks compartilhados
└── features/             ← TUDO específico de feature aqui
    ├── appointments/
    │   ├── api/          ← chamadas pra backend
    │   ├── components/   ← UI específica
    │   ├── hooks/        ← hooks específicos
    │   ├── types/
    │   └── index.ts      ← API pública da feature
    └── billing/
```

## G. Domain-Driven Design (quando aplicar)

**Não aplicar DDD** em todo lugar. **Aplicar** quando:

- Domínio do negócio é complexo (regras de cobrança, planos, descontos)
- Time tem 5+ devs no mesmo domínio
- Business analyst/PM usa vocabulário próprio (Ubiquitous Language)

**Estrutura DDD-light:**

```
modules/billing/
├── domain/               ← entidades + value objects + regras (zero deps)
│   ├── invoice.ts
│   ├── money.value.ts
│   └── billing.policy.ts
├── application/          ← use cases (orquestra domain + infra)
│   ├── create-invoice.use-case.ts
│   └── apply-discount.use-case.ts
├── infrastructure/       ← Prisma, Stripe, etc.
│   └── invoice.prisma.repo.ts
└── presentation/         ← Controller (NestJS) ou Server Action
    └── invoice.controller.ts
```

Domain **nunca** importa de infrastructure (regra de ouro).

## H. Circular dependencies

Detecta + falha CI:

```bash
npx madge --circular src/
# OR
npx depcruise --validate src/
```

**Solução padrão:**
1. Extrair a parte compartilhada pra módulo "shared"
2. Ou aplicar Dependency Inversion (interface no lado certo)

## I. Dead code

```bash
# TypeScript
npx ts-prune
npx knip                  # mais moderno, detecta deps unused também

# Python
vulture src/
```

**Regra:** `knip --reporter terminal` em CI. PR não passa se introduzir morto.

Exceções comuns documentadas em `.knip.json`:
- Entry points
- Type exports usados externamente
- Server actions (Next.js)

## J. Refactor gradual (nunca big-bang)

Migração de estrutura segue **strangler fig**:

```
1. Define nova estrutura ao lado da antiga
2. Mover 1 feature por sprint
3. Quando todas migradas, deleta a antiga
4. Migração que dura > 6 meses = NÃO COMEÇA (falha de plano)
```

Greps automatizados detectam progresso:
```bash
# % de imports usando alias novo vs antigo
grep -r "from '@/features/" src | wc -l           # novo
grep -r "from '../../features/" src | wc -l       # antigo (deveria ir a zero)
```

## K. Greps obrigatórios

```bash
# Importação direto entre features (PROIBIDO)
rg -n "from ['\"]@/features/([^/]+)/" --type ts | \
  awk -F'from' '{print $2}' | sort -u

# Use relativos profundos (../../) — sinal de path mapping faltando
rg -n "from ['\"]\\.\\.\\/\\.\\.\\/\\.\\.\\/" --type ts | head -20

# Componente em pasta errada (Button.tsx em /hooks/)
find src/hooks -name '*.tsx' 2>/dev/null
find src/lib -name '*.tsx' 2>/dev/null

# index.ts > 50 linhas
find src -name 'index.ts' | xargs -I {} sh -c '[ $(wc -l < {}) -gt 50 ] && echo "barrel grande: {}"'

# utils/helpers/common files
find src \( -name 'utils.ts' -o -name 'helpers.ts' -o -name 'common.ts' -o -name 'misc.ts' \)

# Arquivos > 400 LOC
find src -type f \( -name '*.ts' -o -name '*.tsx' -o -name '*.py' \) \
  -exec sh -c 'lc=$(wc -l < "$1"); [ $lc -gt 400 ] && echo "$lc $1"' _ {} \; | sort -rn

# Componentes RSC com 'use client' desnecessário
rg -l "'use client'" --type tsx | xargs -I {} sh -c \
  'grep -lq "useState\|useEffect\|useRef" {} || echo "use-client sem motivo: {}"'

# Server-only marker missing em código com process.env.SECRET
rg -l "process\.env\.[A-Z_]*SECRET" --type ts | \
  xargs grep -L "import 'server-only'"
```

## L. Output esperado em sec.html

```
┌─ Architecture (Módulo 14) ───────────────────────────────┐
│ Blueprint detectado          : Next.js 15 + RSC ✅        │
│ tsconfig paths configurados  : ✅ @/lib, @/features      │
│ dependency-cruiser ativo     : ✅ no CI                   │
│ Boundaries violadas          : 0 ✅                       │
│ Circular dependencies        : 0 ✅                       │
│ utils.ts genérico            : 0 (eram 3 → renomeados)    │
│ Arquivos > 400 LOC           : 0 ✅ (eram 5 → quebrados)  │
│ Dead code (knip)             : 0 ✅                       │
│ Componente em pasta errada   : 0 ✅                       │
│ Imports relativos profundos  : 0 ✅                       │
│ 'use client' desnecessário   : 0 ✅                       │
│ Naming convention compliance : 100% ✅                    │
│ Status                       : ✅ WELL-STRUCTURED         │
└───────────────────────────────────────────────────────────┘
```

## M. Anti-padrões (CRIT)

- ❌ `utils.ts` / `helpers.ts` / `common.ts` no projeto (sempre nomear por domínio)
- ❌ Importação direta entre features (`features/A` → `features/B`)
- ❌ Componente importando de `app/` / `pages/`
- ❌ `lib/` importando de `components/`
- ❌ Domain importando de infrastructure (DDD violation)
- ❌ Dependência circular (qualquer ciclo)
- ❌ `index.ts` barril com > 50 linhas (re-export demais)
- ❌ Path relativo `../../../../` (path mapping faltando)
- ❌ Componente RSC com `'use client'` sem `useState`/`useEffect`/`useRef`
- ❌ Arquivo > 600 LOC (smell quase certo)
- ❌ Mistura de naming (`UserProfile.tsx` e `user_profile.tsx` no mesmo projeto)
- ❌ Test importando de fixture de produção
- ❌ Module em monorepo (app/A) importando de outro app (app/B)
- ❌ Refactor big-bang (>6 meses) — quebrar em strangler fig
- ❌ Server-only código (`process.env.SECRET`) sem `import 'server-only'`

## N. Intelligence (⭐ v0.20) — detecção de variações válidas

Architect NÃO força App Router em projeto Pages Router, nem feature-based
em projeto que escolheu layer-based conscientemente.

Lê `.blindar/intelligence.yml`:

```yaml
architect:
  router_mode:
    auto_detect: true        # default
    # Override manual se detecção falhar:
    # mode: pages-router | app-router | both

  structure_style:
    auto_detect: true
    # Override:
    # style: feature-based | layer-based | hybrid

  blueprint_overrides:
    # Quando o projeto escolheu padrão diferente do recommended
    nextjs_pages_router_allowed_paths:
      - "pages/api/**"
      - "pages/**/*.tsx"
    # NÃO aplicar regras de App Router (RSC, server actions) aqui

  custom_aliases:
    # tsconfig paths que o time configurou diferente
    "@app/*": "src/app/*"
    "@shared/*": "shared/*"

  allowed_top_level_dirs:
    # Pastas custom que NÃO são erradas
    - "infra"               # Terraform/Pulumi
    - "k8s"                 # manifests
    - "docs"
    - "scripts"

  ignore_size_limit_in:
    # Arquivos onde tamanho > 400 LOC é aceitável
    - "**/*.gen.ts"          # gerado
    - "**/openapi-types.ts"  # spec gigante
    - "**/schema.prisma"     # schema único
    - "**/i18n/**"           # locales podem ser grandes
```

### Auto-detecção de Router

```ts
function detectNextjsRouter(projectDir) {
  const hasApp = fs.existsSync(path.join(projectDir, 'app'));
  const hasPages = fs.existsSync(path.join(projectDir, 'pages'));
  if (hasApp && !hasPages) return 'app-router';
  if (!hasApp && hasPages) return 'pages-router';
  if (hasApp && hasPages) return 'both';  // transição
  return 'unknown';
}
```

Em modo `pages-router`:
- Não exige `metadata` export
- Não acusa `getServerSideProps` (é o padrão)
- Não exige `'use client'` (todos são client)
- NÃO sugere strangler-fig pra App Router (decisão do operador)

Em modo `app-router`:
- Acusa `getServerSideProps` (deprecated)
- Exige `metadata` export
- Acusa `'use client'` desnecessário

### Markers no código

```ts
// @blindar:keep-structure -- mantida assim por decisão arquitetural
// Ver docs/adr/0012-keep-layered-structure.md
```

Architect respeita e não sugere refactor.

### Detecção de Vue / Svelte / Astro / outros

Se detectar `vite.config.ts` com `vue`, `svelte`, `astro` em plugins,
muda blueprint completamente. Não força Next.js patterns.

## O. Interação com outros agentes

- **db-architect**: define estrutura do banco; este define estrutura do código
- **api-design**: define contratos; este garante onde os controllers/routers ficam
- **config-externalization**: tira hardcode; este garante onde a config mora
- **documentation-live**: documenta decisões; este aplica na estrutura
- **mock-killer**: tira mocks; este garante onde testes vivem
- **testing-strategy**: define pirâmide; este garante onde cada teste mora
