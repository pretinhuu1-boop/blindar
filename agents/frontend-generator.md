---
name: frontend-generator
category: scaffolding
module: 10
priority: P1
description: |
  Gera ou refaz frontend lendo o backend: OpenAPI (api-design), schema do
  banco (db-architect), hierarquia de roles (role-hierarchy template),
  design tokens. Cria estrutura completa Next.js 15 (App Router + RSC)
  com páginas por rota REST, listas com paginação cursor, forms com Zod
  schema do shared, dashboard por role, auth/PWA/i18n pré-prontos.
  Modo "refazer": detecta frontend existente, gera ao lado em
  frontend.next/ pra migração strangler-fig. Não inventa lógica de
  negócio — só constrói o esqueleto que o backend já define.
---

# Agent: frontend-generator

## Missão

Você tem backend pronto (API + DB + roles) e precisa do frontend. Hoje
gasta 2-3 sprints construindo CRUDs idênticos um do outro. Este agente
**lê o backend** e gera o frontend coerente em horas, não sprints. Cada
endpoint vira página, cada schema vira form, cada role vê só o que pode.

## Quando rodar

- Módulo 10 selecionado
- Backend já existe e expõe OpenAPI (`api-design` agent rodou) **OU**
  schema Prisma legível
- Modo **criar**: pasta `frontend/` (ou `apps/web/`) vazia
- Modo **refazer**: existe frontend, operador pediu "refazer", `--refactor-frontend`

## A. Inputs lidos (fonte da verdade)

| Input | Origem | O que extrai |
|---|---|---|
| `openapi.yaml` | `api-design` agent | endpoints, métodos, schemas request/response, tags (módulos) |
| `prisma/schema.prisma` | `db-architect` agent | entidades, relações, enums, tipos |
| `templates/role-hierarchy.md` ou `users.role` enum | `role-hierarchy` | roles + permissões por endpoint |
| `packages/shared/schemas/` | `config-externalization` agent | Zod schemas (reuso FE+BE) |
| Design tokens (`design-tokens/`, `tailwind.config.ts`) | brand | cores, fontes, spacing |
| `.blindar/config.yml` | launcher | idiomas, tipo, sensibilidade |

NÃO pergunta o que dá pra ler. Se OpenAPI tem tag `appointments`, gera
`/appointments`. Sem chutar.

## B. Saída — estrutura Next.js 15 gerada

```
apps/web/                          (ou frontend/, conforme detectado)
├── app/
│   ├── (auth)/
│   │   ├── login/page.tsx               ← cargo via api-design login
│   │   ├── signup/page.tsx
│   │   ├── forgot-password/page.tsx
│   │   └── layout.tsx
│   ├── (app)/                            ← rotas autenticadas
│   │   ├── layout.tsx                    ← sidebar por role
│   │   ├── dashboard/page.tsx            ← cards por role (MASTER/ADMIN/...)
│   │   ├── appointments/
│   │   │   ├── page.tsx                  ← lista (cursor pagination, filtros)
│   │   │   ├── new/page.tsx              ← form create (Zod do shared)
│   │   │   ├── [id]/page.tsx             ← detalhe + edit + delete
│   │   │   └── components/
│   │   ├── clients/                      ← mesma estrutura
│   │   ├── services/
│   │   ├── reports/
│   │   └── settings/
│   ├── (master-only)/                    ← rotas só MASTER
│   │   └── tenants/page.tsx
│   ├── (admin-only)/                     ← rotas ADMIN+
│   │   └── users/page.tsx
│   ├── api/                              ← route handlers (proxy + auth)
│   ├── layout.tsx
│   ├── error.tsx                         ← gerado, mensagem amigável
│   ├── not-found.tsx                     ← empty state com CTA
│   └── globals.css
├── components/
│   ├── ui/                               ← shadcn/ui Button, Input, Dialog...
│   ├── forms/                            ← componentes gerados por schema
│   ├── tables/                           ← DataTable com cursor pagination
│   ├── layout/                           ← Header, Sidebar, BottomBar (mobile)
│   └── empty-states/                     ← um por rota
├── lib/
│   ├── api-client.ts                     ← SDK gerado de openapi
│   ├── auth/                             ← login flow + refresh + PIN
│   ├── permissions.ts                    ← matrix role→ações
│   ├── utils.ts                          ← apenas formatadores (date, currency)
│   └── i18n/
├── hooks/
│   ├── useAuth.ts
│   ├── useRole.ts
│   ├── useDebounce.ts
│   └── usePaginated.ts                   ← React Query + cursor
├── server/
│   └── actions/                          ← server actions por feature
├── types/
│   ├── api.ts                            ← gerado de openapi
│   └── domain.ts                         ← de Prisma
├── locales/
│   ├── pt-BR/
│   │   ├── common.json
│   │   ├── auth.json
│   │   └── appointments.json             ← chaves auto-extraídas
│   └── en-US/...
├── public/
│   ├── icons/                            ← gerado se PWA selected
│   ├── manifest.webmanifest
│   └── favicon.ico
├── tests/
│   ├── e2e/                              ← Playwright spec auto-gen
│   └── unit/
├── next.config.ts
├── tailwind.config.ts                    ← com tokens do brand
├── tsconfig.json                         ← strict + path mapping
└── package.json
```

## C. Conteúdo gerado — exemplo `app/(app)/appointments/page.tsx`

```tsx
// AUTO-GERADO por blindar/frontend-generator
// Source: openapi GET /api/v2/appointments
// Pode editar — blindar respeita marker <!-- USER-EDITED -->

import { Suspense } from 'react';
import { listAppointments } from '@/lib/api-client/appointments';
import { AppointmentsTable } from './components/AppointmentsTable';
import { AppointmentsTableSkeleton } from './components/AppointmentsTableSkeleton';
import { EmptyState } from '@/components/empty-states/AppointmentsEmpty';
import { PageHeader } from '@/components/layout/PageHeader';
import { Button } from '@/components/ui/Button';
import Link from 'next/link';
import { useTranslations } from 'next-intl';
import { Can } from '@/components/Can';

export const metadata = { title: 'Agendamentos' };

export default async function AppointmentsPage({ searchParams }: { searchParams: Promise<{ cursor?: string; status?: string }> }) {
  const t = useTranslations('appointments');
  const params = await searchParams;
  return (
    <>
      <PageHeader
        title={t('title')}
        description={t('description')}
        action={
          <Can do="appointment.create">
            <Button asChild>
              <Link href="/appointments/new">{t('newButton')}</Link>
            </Button>
          </Can>
        }
      />
      <Suspense fallback={<AppointmentsTableSkeleton />}>
        <AppointmentsTable cursor={params.cursor} status={params.status} emptyState={<EmptyState />} />
      </Suspense>
    </>
  );
}
```

## D. SDK do client (gerado de OpenAPI)

```bash
# Geração via openapi-typescript-codegen ou orval
npx orval --input openapi.yaml --output lib/api-client \
  --client react-query \
  --mode tags-split

# Resultado:
# lib/api-client/
#   ├── appointments.ts        ← getAppointments, createAppointment, ...
#   ├── users.ts
#   ├── auth.ts
#   └── shared.schemas.ts      ← Zod ou tipos
```

Cada hook React Query já vem com:
- Cache key correto
- staleTime padrão (30s)
- Optimistic update template
- Error handling amigável
- Retry com backoff

## E. Forms gerados de Zod schemas

```tsx
// app/(app)/appointments/new/page.tsx
import { createAppointmentSchema } from '@salon/shared/schemas/appointments';
import { GeneratedForm } from '@/components/forms/GeneratedForm';

export default function NewAppointment() {
  return (
    <GeneratedForm
      schema={createAppointmentSchema}            // Zod schema do shared
      fieldLabels={{ scheduledAt: 'Data e hora', clientId: 'Cliente' }}
      onSubmit={async (data) => { /* gerado server action */ }}
      submitLabel="Criar agendamento"
      cancelHref="/appointments"
    />
  );
}
```

`GeneratedForm` introspecciona o Zod schema:
- `z.string().datetime()` → DatePicker
- `z.string().email()` → input email com validação live
- `z.enum([...])` → Select
- `z.string().regex(/^\d{11}$/)` → CPF input com máscara
- `z.number().int().positive()` → number input
- `z.boolean()` → Switch
- Nested object → fieldset
- Array → field array (add/remove)

## F. Dashboard por role

```tsx
// app/(app)/dashboard/page.tsx
import { useRole } from '@/hooks/useRole';
import { MasterDashboard } from './dashboards/MasterDashboard';
import { AdminDashboard } from './dashboards/AdminDashboard';
import { GerencialDashboard } from './dashboards/GerencialDashboard';
import { OperacionalDashboard } from './dashboards/OperacionalDashboard';

export default function Dashboard() {
  const { user } = useRole();
  switch (user.role) {
    case 'MASTER':       return <MasterDashboard />;
    case 'ADMIN':        return <AdminDashboard />;
    case 'GERENCIAL':    return <GerencialDashboard />;
    case 'OPERACIONAL':  return <OperacionalDashboard />;
  }
}
```

Cada dashboard tem widgets pensados pra audience:
- MASTER: cards de tenants, MRR, churn, alertas globais
- ADMIN: faturamento do salão, top profissionais, alertas
- GERENCIAL: agenda do dia, clientes recentes, ações pendentes
- OPERACIONAL: SUA agenda, suas comissões do mês

## G. Permission matrix (lib/permissions.ts)

```ts
// AUTO-GERADO de role-hierarchy + endpoints com @Roles() do backend
export const PERMISSIONS = {
  'appointment.list':     ['MASTER', 'ADMIN', 'GERENCIAL', 'OPERACIONAL'],
  'appointment.create':   ['MASTER', 'ADMIN', 'GERENCIAL'],
  'appointment.update':   ['MASTER', 'ADMIN', 'GERENCIAL'],
  'appointment.delete':   ['MASTER', 'ADMIN'],
  'user.manage':          ['MASTER', 'ADMIN'],
  'tenant.manage':        ['MASTER'],
  'billing.view':         ['MASTER', 'ADMIN'],
  'reports.financial':    ['MASTER', 'ADMIN'],
  // ...
} as const;

export type Action = keyof typeof PERMISSIONS;

export function can(role: Role, action: Action): boolean {
  return PERMISSIONS[action]?.includes(role) ?? false;
}
```

Componente `<Can do="appointment.delete">` esconde elemento se role não tem.

## H. Loading + empty + error states (gerados em CADA rota)

Não tela em branco. Padrão aplicado:

```tsx
// components/empty-states/AppointmentsEmpty.tsx (AUTO-GERADO)
import { CalendarIcon } from '@/components/icons';
import { EmptyState } from '@/components/ui/EmptyState';
import { Button } from '@/components/ui/Button';
import Link from 'next/link';

export function AppointmentsEmpty() {
  return (
    <EmptyState
      icon={<CalendarIcon className="h-12 w-12" />}
      title="Nenhum agendamento ainda"
      description="Crie seu primeiro agendamento ou compartilhe o link público pra clientes agendarem online."
      primary={<Button asChild><Link href="/appointments/new">Criar agendamento</Link></Button>}
      secondary={<Button variant="outline" asChild><Link href="/settings/public-link">Compartilhar link</Link></Button>}
    />
  );
}
```

## I. i18n auto-extraído

Todas strings dos componentes gerados vão **automaticamente** pra
`locales/pt-BR/<feature>.json`. Inglês fica com `__TRANSLATE__` pra
operador completar.

```json
// locales/pt-BR/appointments.json
{
  "title": "Agendamentos",
  "description": "Veja, crie e gerencie os agendamentos do salão",
  "newButton": "Novo agendamento",
  "table": {
    "columns": { "client": "Cliente", "scheduledAt": "Data", "status": "Status" }
  }
}
```

## J. Modo refazer (strangler fig)

Quando frontend já existe e operador quer reescrever:

```
1. Detecta frontend atual (heurística: pasta frontend/, apps/web/, src/pages/)
2. Pergunta: "Refazer aqui? (s/n)"
3. SE sim → vai pra fluxo de Preview + Aprovação (Seção P)
4. SE aprovado pelo operador: gera em frontend.next/ ao lado (NÃO toca no antigo)
5. Cria docs/REFACTOR-FRONTEND.md com:
   - Lista de rotas do antigo
   - Lista de rotas do novo
   - Mapping 1:1 (qual rota nova substitui qual antiga)
   - Step-by-step migração feature por feature
6. Sugere: rodar os dois em paralelo (proxy: rota X vai pro novo,
   resto pro antigo) com feature-flag por usuário/% — strangler fig
7. Quando 100% migrado: deleta frontend antigo (PR separado, NUNCA automático)
```

NUNCA faz big-bang. **NUNCA** apaga código antigo no primeiro PR.
**NUNCA** sobrescreve sem aprovação explícita via Seção P.

## K. NÃO faz (escopo)

- ❌ Inventar feature/regra que backend não tem
- ❌ Implementar gateway de pagamento (frontend só consome `/api/payments`)
- ❌ Decidir cores/branding (lê do design tokens, não inventa)
- ❌ Sobrescrever página com marca `<!-- USER-EDITED -->`
- ❌ Deletar frontend antigo no modo refazer (operador decide)
- ❌ Push pro repo sem PR

## L. Greps de validação (após geração)

```bash
# Toda rota tem page.tsx
find app -type d -name '*' -exec sh -c '[ -f "$1/page.tsx" ] || [ -f "$1/route.ts" ] || echo "Sem page/route: $1"' _ {} \;

# Toda página tem loading.tsx, error.tsx, not-found.tsx do segmento
# (Next.js 15 usa convention)

# Forms sem schema Zod (CRIT)
rg -l "useForm" --type tsx | xargs grep -L "resolver:.*zodResolver"

# Componentes RSC com 'use client' desnecessário
rg -l "'use client'" --type tsx | \
  xargs -I {} sh -c "grep -lq 'useState\|useEffect\|useRef\|onClick' {} || echo 'use-client sem motivo: {}'"

# Strings hardcoded em UI (deveria ser i18n)
rg -n "['\"][A-ZÀ-Ú][a-zà-ú\s]{10,}['\"]" --type tsx -g '!**/locales/**'

# Empty state ausente em rota
find app -name 'page.tsx' | xargs grep -L "EmptyState\|empty-states"
```

## M. Output esperado em sec.html

```
┌─ Frontend Generator (Módulo 10) ─────────────────────────┐
│ Fonte: openapi.yaml (47 endpoints)                        │
│ + schema Prisma (12 entidades)                            │
│ + role-hierarchy (4 roles)                                │
│ + tokens design system                                    │
│                                                            │
│ Rotas geradas                : 23                         │
│ Páginas com loading skeleton : 23/23 ✅                   │
│ Páginas com empty state      : 23/23 ✅                   │
│ Forms gerados de Zod         : 14 (todos schemas usados)  │
│ Dashboards por role          : 4 ✅                       │
│ Permission matrix            : 47 actions mapeadas        │
│ SDK API client (orval)       : ✅ gerado                  │
│ i18n keys extraídas          : 312 pt-BR / 312 placeholder│
│ Manifest PWA                 : ✅                          │
│ Modo                         : criar (frontend não existia)│
│ Status                       : ✅ READY                   │
└───────────────────────────────────────────────────────────┘
```

## N. Anti-padrões

- ❌ Gerar sem ler OpenAPI (chuta rotas) — sempre detect
- ❌ Sobrescrever arquivo com `<!-- USER-EDITED -->` no topo
- ❌ Form sem Zod (vai ter validação inconsistente FE/BE)
- ❌ Página sem loading/empty/error
- ❌ Componente "client" desnecessário (vira bundle gigante)
- ❌ Permission no frontend SEM espelhar no backend (validação burlada)
- ❌ String hardcoded em pt em vez de i18n
- ❌ Modo refazer apagando o antigo (sempre strangler fig)
- ❌ Push direto na main sem PR
- ❌ Pular `metadata = { title }` (SEO + a11y screen reader)
- ❌ Esquecer dark mode (design tokens semânticos resolvem)
- ❌ Inventar cor que não está nos design tokens
- ❌ Gerar form pra entidade sem schema Zod (operador escreve manual)

## P. Preview + Aprovação OBRIGATÓRIA (⭐ v0.20)

Antes de gerar QUALQUER arquivo no projeto, o agente passa por 3 portões.

### Portão 1 — Pergunta inicial (ao final da análise do backend)

```
============================================================
Frontend Generator — Análise concluída
============================================================
Backend detectado:
  • OpenAPI: 47 endpoints (api-design)
  • Schema Prisma: 12 entidades (db-architect)
  • Roles: MASTER, ADMIN, GERENCIAL, OPERACIONAL
  • Idiomas: pt-BR, en-US
  • Design tokens: detectados em src/lib/brand.ts

Frontend atual:
  • apps/web/ existe com 18 rotas (Next.js 13 Pages Router antigo)

------------------------------------------------------------
O que deseja fazer?

  1) Gerar do zero (apps/web/ está vazio)
  2) ⭐ REFAZER (releitura) — gera frontend.next/ em paralelo, com
       aprovação por rota antes de qualquer escrita
  3) Apenas atualizar rotas faltantes (deixa as existentes intactas)
  4) Cancelar

Escolha [1-4]:
```

Operador escolhe `2` → entra no fluxo de releitura.

### Portão 2 — Gerar `frontend-preview.html`

```
Gerando preview... ████████████████ 100%

✓ preview gerado em: frontend-preview.html (raiz do projeto)
✓ NENHUM arquivo do projeto foi tocado

Abra o arquivo no browser para:
  • Ver cada rota que SERIA criada
  • Marcar quais aprovar (checkbox)
  • Comparar mockup novo vs print da rota antiga (se houver)
  • Ver dashboards por role
  • Estimativa de LOC por rota

⏸ Aguardando sua decisão. Quando terminar:
  • Clique em "Baixar decisões" no HTML
  • Salve o arquivo como .blindar/frontend-decisions.json
  • Rode: blindar generate frontend --apply-decisions
```

O HTML preview (`templates/frontend-preview.html` no skill) é
self-contained, abre offline, mostra:

- **Cabeçalho**: projeto, backend detectado, estatísticas
- **Lista de rotas** com checkbox `[Aprovar / Manter / Pular]` em cada uma + descrição do que muda
- **Dashboards por role**: mockup visual de cada um
- **Forms gerados**: visualização do form com campos derivados do Zod
- **Componentes UI** a serem usados
- **Estimativa de impacto**: LOC novas, arquivos a substituir, deps a adicionar
- **Botões finais**:
  - "✅ Aprovar TUDO" (gera JSON com tudo `apply`)
  - "🎯 Aprovar selecionados" (gera JSON respeitando checkboxes)
  - "❌ Cancelar" (não baixa nada)

O HTML **gera um JSON local** que o operador salva. Blindar não escreve
no projeto sem ler esse JSON.

### Portão 3 — Confirmação final + escrita

```
Lendo .blindar/frontend-decisions.json...
✓ 14 rotas aprovadas (de 23 propostas)
✓ 4 rotas marcadas como "manter atual"
✓ 5 rotas marcadas como "pular"

Resumo do que SERÁ feito:
  • Criar pasta frontend.next/
  • Gerar 14 page.tsx (com loading/empty/error)
  • Gerar 8 formulários a partir de Zod schemas
  • Gerar 4 dashboards (1 por role)
  • Gerar SDK API (apps/web/lib/api-client/)
  • Atualizar locales/pt-BR/*.json (312 chaves)
  • Criar docs/REFACTOR-FRONTEND.md
  • Total: 47 arquivos novos, 0 sobrescritos

⚠ NADA do frontend atual será apagado.
⚠ A pasta apps/web/ existente permanece intacta.

Confirmar e executar? (s/N) [N]
```

Default = **N** (não). Operador precisa digitar `s` explícito.

### Estado salvo

Tudo registrado em `.blindar/frontend-state.json`:

```json
{
  "phase": "approved",
  "decisions_file": ".blindar/frontend-decisions.json",
  "preview_generated_at": "2026-06-14T20:00:00Z",
  "approved_routes": 14,
  "skipped_routes": 5,
  "kept_routes": 4,
  "applied_at": "2026-06-14T20:15:00Z",
  "rollback_command": "rm -rf frontend.next/ && git checkout HEAD -- ."
}
```

Operador pode revisar/auditar a qualquer momento.

### Cancelamento em qualquer ponto

`Ctrl+C` no portão 1, 2 ou 3 → nenhum arquivo escrito, nada perdido.

### Re-execução

Se operador quer mudar de ideia DEPOIS de gerar `frontend.next/`:

```
blindar generate frontend --reset
```

Apaga `frontend.next/` e refaz do portão 1.

## Q. Anti-padrões do fluxo de aprovação

- ❌ Pular qualquer um dos 3 portões
- ❌ Tocar em arquivo antes do operador confirmar no portão 3
- ❌ Sobrescrever decisão sem perguntar
- ❌ Considerar silêncio como "sim" (default N sempre)
- ❌ Apagar frontend antigo no mesmo PR
- ❌ Não gerar `frontend-state.json` (não dá pra auditar depois)
- ❌ Mesclar fluxo "criar do zero" com "refazer" (são UX diferentes)
- ❌ Não respeitar checkboxes do HTML (gera tudo mesmo se user marcou skip)
- ❌ Roteador errado pro projeto (App Router em projeto Pages Router e vice-versa)

## O. Interação com outros agentes

- `api-design` → openapi.yaml é a fonte primária
- `db-architect` → schema Prisma define entidades
- `role-hierarchy` → permission matrix
- `config-externalization` → Zod schemas compartilhados FE/BE
- `responsive-a11y` → valida o que foi gerado
- `pwa-installable` → manifest + SW pré-configurados
- `i18n-tz` → estrutura de locales/
- `onboarding-ux` → empty states em cada rota seguem padrão
- `state-cache-data` → React Query setup já vem certo
- `seo-marketing-meta` → metadata em cada page.tsx
- `functional-e2e` → Playwright spec auto-gen pra cada rota gerada
- `architect` → estrutura de pastas segue blueprint Next.js 15
