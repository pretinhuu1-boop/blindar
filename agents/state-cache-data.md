---
name: state-cache-data
category: frontend
module: 10
priority: P1
description: |
  Fluidez de dados no client: optimistic UI, SWR/React Query, cache
  invalidation correta, offline-first com Service Worker, conflict
  resolution (last-writer-wins é ruim — use CRDT ou versioning), sync
  engine, suspense + streaming. Aplicação parece instantânea mesmo em
  conexão ruim.
---

# Agent: state-cache-data

## Missão

App moderno não pode esperar request síncrono pra responder ao clique do
user. Optimistic UI + cache inteligente + sync em background = experiência
"local-first" que parece instantânea. Este agente prescreve o padrão.

## Quando rodar

- Módulo 10 selecionado E `ui_detected: true`
- Operador pediu "rápido", "fluido", "sem loading", "offline"

## A. Stack de data fetching

| Lib | Quando |
|---|---|
| **TanStack Query** (React Query) v5 | Default — REST/GraphQL, mature, offline OK |
| **SWR** | Alternativa simpler, Vercel-aligned |
| **tRPC + React Query** | Monorepo TS end-to-end |
| **Apollo Client** | GraphQL pesado, com cache normalizado |
| **Relay** | Facebook-tier scale, learning curve alta |

NUNCA: `useEffect + fetch + useState` manual em hot path (perde dedup,
retry, cache, focus refetch).

## B. Optimistic UI

```ts
// React Query optimistic update
const mutation = useMutation({
  mutationFn: updateAppointment,
  onMutate: async (newData) => {
    await queryClient.cancelQueries({ queryKey: ['apt', id] });
    const previous = queryClient.getQueryData(['apt', id]);
    queryClient.setQueryData(['apt', id], (old) => ({ ...old, ...newData }));
    return { previous };
  },
  onError: (err, vars, ctx) => {
    queryClient.setQueryData(['apt', id], ctx.previous);  // rollback
    toast.error('Falha ao salvar. Tentando de novo...');
  },
  onSettled: () => queryClient.invalidateQueries({ queryKey: ['apt', id] })
});
```

### Regras

- Optimistic SÓ pra operações que **provavelmente** vão dar certo (update simples)
- NUNCA optimistic em pagamento, criar conta, deletar (espera confirmação)
- Sempre ter `onError` que faz rollback + toast amigável
- Mostrar estado "saving..." sutil (não bloquear UI)

## C. Cache invalidation

### Hierarquia de invalidação

```ts
// Após criar appointment:
queryClient.invalidateQueries({ queryKey: ['appointments'] });          // lista
queryClient.invalidateQueries({ queryKey: ['stats', 'dashboard'] });    // métricas
queryClient.setQueryData(['apt', newApt.id], newApt);                   // detalhe (set, não invalidate)
```

### Por escopo

| Escopo | Quando invalidar |
|---|---|
| Item específico (`['apt', id]`) | Update direto desse item |
| Lista (`['apt-list']`) | Create/delete (afeta paginação) |
| Métricas/dashboard | Mudança que afeta agregado |
| User-scoped (`['apt', { userId }]`) | Mudança em apt desse user |
| Tudo (`queryClient.clear()`) | Logout, troca de tenant |

### Stale-while-revalidate

```ts
useQuery({
  queryKey: ['apt', id],
  queryFn: () => fetchApt(id),
  staleTime: 30_000,    // 30s "fresh" — não refaz
  gcTime: 5 * 60_000,   // 5min em cache mesmo se unused
  refetchOnWindowFocus: true,
  refetchOnReconnect: true
});
```

## D. Offline-first

### Estratégia em camadas

1. **Cache de leitura** (Service Worker / Workbox NetworkFirst com fallback)
2. **Queue de escrita** (IndexedDB pra mutations pendentes)
3. **Background sync** (registra mutations enquanto offline, sync ao voltar)
4. **Conflict resolution** (server-side decide; client mostra resolução)

```ts
// React Query + persistência IndexedDB
import { persistQueryClient } from '@tanstack/react-query-persist-client';
import { createSyncStoragePersister } from '@tanstack/query-sync-storage-persister';
import { get, set, del } from 'idb-keyval';

persistQueryClient({
  queryClient,
  persister: createSyncStoragePersister({
    storage: { getItem: get, setItem: set, removeItem: del }
  }),
  maxAge: 24 * 60 * 60 * 1000  // 24h
});
```

### Mutations offline

```ts
const m = useMutation({
  mutationFn: createApt,
  networkMode: 'offlineFirst',   // tenta agora, falha → fila
  retry: 5,
  retryDelay: (i) => Math.min(1000 * 2 ** i, 30000)
});

// Indicar pendentes na UI
const pending = useIsMutating({ mutationKey: ['create-apt'] });
{pending > 0 && <Badge>{pending} pendente(s) — sincronizando…</Badge>}
```

## E. Conflict resolution

### Estratégias

| Estratégia | Quando |
|---|---|
| **Last-writer-wins** | Operações idempotentes, baixo risco |
| **Optimistic locking** (`version` column) | Default pra mutations críticas — 409 se versão divergiu |
| **CRDT** (Yjs/Automerge) | Edição colaborativa real (Docs, Figma-like) |
| **Server-decides + UI conflito** | Apresenta as 2 versões pro user escolher |

### Optimistic locking (mais comum)

```ts
// Backend: rejeita se versão divergiu
@Patch(':id')
async update(@Param('id') id, @Body() dto: UpdateDto) {
  const updated = await this.prisma.appointment.update({
    where: { id, version: dto.version },   // condição
    data: { ...dto.data, version: { increment: 1 } }
  });
  // Se não atualizou nada → conflict
}

// Frontend: mostra modal "Editado por outra pessoa"
if (err.status === 409) {
  showConflictModal({
    yourVersion: dto,
    serverVersion: await fetchApt(id),
    onResolve: (chosen) => mutate({ ...chosen, version: chosen.version })
  });
}
```

## F. Streaming + Suspense (React 19+)

```tsx
// Server Component streamando
export default async function Page() {
  return (
    <>
      <Header />
      <Suspense fallback={<Skeleton />}>
        <AppointmentList />   {/* renderiza quando dados chegam */}
      </Suspense>
      <Suspense fallback={<Skeleton />}>
        <Stats />              {/* renderiza independente */}
      </Suspense>
    </>
  );
}
```

Resultado: cada bloco aparece quando pronto. TTFB rápido, LCP otimizado.

## G. Prefetch inteligente

```ts
// Hover em link → prefetch da próxima página
<Link
  href={`/appointments/${id}`}
  onMouseEnter={() => queryClient.prefetchQuery({
    queryKey: ['apt', id],
    queryFn: () => fetchApt(id),
    staleTime: 10_000
  })}
>
  Ver detalhes
</Link>
```

Navegação parece instantânea (dados já estão em cache quando user clica).

## H. Sync engine alternativo (futuro)

Quando paradigma "request/response" não cobre:
- **Replicache / Rocicorp Zero** — sync engine declarativo, conflict-free
- **Linear's sync engine** — bidirectional, offline-first
- **PowerSync / ElectricSQL** — Postgres ↔ SQLite no client
- **Y.js + y-websocket** — CRDT pra edição colaborativa

Avaliar se app tem **dados altamente compartilhados em tempo real**
(documentos colaborativos, kanban multi-user, dashboards live).

## Output esperado em sec.html

```
┌─ State / Cache / Data (Módulo 10) ───────────────────────┐
│ Data fetching lib            : TanStack Query v5 ✅       │
│ Optimistic UI em mutations   : ✅ 12/14 elegíveis         │
│ Cache invalidation correta   : ✅ todos endpoints         │
│ Stale-while-revalidate       : ✅ staleTime configurado   │
│ Offline-first reads          : ✅ Workbox cache           │
│ Offline-first mutations      : ✅ retry queue persistente │
│ Conflict resolution          : optimistic-lock + 409 UI ✅│
│ Prefetch on hover            : ✅ navegação instantânea   │
│ Streaming (Suspense)         : ✅ Server Components       │
│ Indicador "syncing"          : ✅ visível ao user         │
│ Status                       : ✅ FLUID                   │
└───────────────────────────────────────────────────────────┘
```

## Anti-padrões

- ❌ `useEffect + fetch` em produção (perde dedup, retry, cache)
- ❌ Optimistic em pagamento (rollback = cliente perdeu confiança)
- ❌ Invalidação "tudo a cada mutation" (refaz queries desnecessárias)
- ❌ Last-writer-wins em entidade crítica sem aviso de conflito
- ❌ Mutation que apaga UI antes de confirmar (sumiu sem feedback)
- ❌ Loading spinner gigante quando dado já está em cache
- ❌ Não invalidar lista após create/delete (paginação suja)
- ❌ Cache infinito sem `gcTime` (memory leak no SPA longo)
- ❌ Offline silencioso (user não sabe que mutações estão na fila)
