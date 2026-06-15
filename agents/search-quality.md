---
name: search-quality
category: frontend
module: 10
priority: P1
description: |
  Busca interna que funciona: Meilisearch/Algolia/pg_trgm com relevância
  por pesos, autocomplete debounced, sync lag < 5s, faceted filters,
  fuzzy matching, sinônimos, search history, highlight, empty state
  com sugestões. Engine como read-model do banco, nunca fonte de verdade.
---

# Agent: search-quality

## Missão

Busca ruim = abandono. "Não acho nada" = "vou pra concorrente". Este
agente prescreve a stack correta + UX que faz o user encontrar.

## Quando rodar

- Módulo 10 selecionado
- Detectado: `meilisearch`, `algoliasearch`, `@elastic/elasticsearch`,
  `typesense`, ou `pg_trgm`/`tsvector` no schema
- Operador pediu "busca", "search", "filtrar lista grande"

## A. Escolha de engine

| Caso | Engine |
|---|---|
| < 1k registros simples | Filter in-memory no front |
| Busca por slug/ID exato | SQL direto |
| Full-text + filtros + < 10k docs | **Meilisearch** (recomendado 2026) |
| Multi-language + cliente JS | **Typesense** alternativa |
| Cliente JS hosted | **Algolia** (caro mas turnkey) |
| Aggregations BI pesadas | **Elasticsearch/OpenSearch** |
| Tudo em Postgres (sem +1 serviço) | `pg_trgm` + `tsvector` cobre 80% |

## B. Engine como read-model (não fonte de verdade)

```ts
// Banco sempre tem o dado real
// Engine sincroniza via:
// - Eventos pós-write (mutação dispara index update)
// - Cron de reconciliação diária (catch up de quem perdeu evento)

async function onAppointmentChange(apt: Appointment) {
  await db.appointment.upsert(...);            // banco primeiro
  await searchQueue.add('index', { id: apt.id });  // event-driven
}
```

NUNCA usar Meilisearch como source of truth — dados sempre vêm do banco.

## C. Relevância com pesos

```ts
// Meilisearch
await index.updateSettings({
  searchableAttributes: ['title', 'tags', 'description'],  // ordem = peso
  rankingRules: [
    'words', 'typo', 'proximity', 'attribute', 'sort', 'exactness',
    'date_added:desc',  // recência manda
  ],
  synonyms: {
    'notebook': ['laptop', 'computador portátil'],
    'celular':  ['smartphone', 'cel'],
  },
  stopWords: ['de', 'da', 'do', 'e', 'a', 'o'],
});
```

## D. Frontend UX (debounce + a11y)

```tsx
const [q, setQ] = useState('');
const dq = useDebounce(q, 300);  // espera 300ms parar de digitar
const { data, isFetching } = useQuery({
  queryKey: ['search', dq],
  queryFn: () => searchApi(dq),
  enabled: dq.length >= 2,        // mínimo 2 chars
  staleTime: 30_000,
});

return (
  <div role="search">
    <label htmlFor="search-input" className="sr-only">Buscar</label>
    <input id="search-input" value={q} onChange={e => setQ(e.target.value)}
           aria-busy={isFetching} aria-controls="search-results" />
    <ul id="search-results" role="listbox">
      {data?.hits?.length === 0 && <EmptyResults q={dq} />}
      {data?.hits?.map(h => <Result key={h.id} hit={h} q={dq} />)}
    </ul>
  </div>
);
```

### Highlight do termo

Engine retorna `_formatted` com `<em>...</em>` — apenas renderizar com
`dangerouslySetInnerHTML` **APÓS sanitize**.

### Empty state com sugestões

```tsx
<EmptyState
  title="Nenhum resultado para '{q}'"
  description="Tente termos mais gerais"
  suggestions={['Cabelo', 'Barba', 'Manicure']}  // top searches
  spellSuggestion={data?.didYouMean}              // "Você quis dizer X?"
/>
```

NUNCA tela em branco.

### Search history

```ts
const recent = JSON.parse(localStorage.getItem('search-history') || '[]');
// Mostrar quando input vazio. Limpar com botão. Máx 5.
```

## E. Filtros facetados

```ts
const results = await index.search(q, {
  filter: ['status = active', `tenant_id = '${tenantId}'`],
  facets: ['category', 'price_range', 'tags'],
  hitsPerPage: 20,
});
// results.facetDistribution: { category: { hair: 23, nails: 12 } }
```

Frontend renderiza checkboxes com contadores.

## F. Sync incremental + reconciliação

```ts
// Worker BullMQ
queue.process('index', async (job) => {
  const apt = await db.appointment.findUnique({ where: { id: job.data.id } });
  if (!apt) return await index.deleteDocument(job.data.id);  // apagado
  await index.addDocuments([{
    id: apt.id, tenant_id: apt.tenantId,
    title: apt.title, description: apt.description, tags: apt.tags,
    date_added: apt.createdAt.toISOString(),
  }]);
});

// Cron de reconciliação (catch up)
cron('0 3 * * *', async () => {
  const dbCount = await db.appointment.count();
  const idxCount = (await index.getStats()).numberOfDocuments;
  if (Math.abs(dbCount - idxCount) > 10) await fullReindex();
});
```

Alertar se sync lag > 5 min.

## G. Multi-tenant

`tenant_id` no filtro de TODA busca. Garantir que cliente não consegue
trocar via param. Backend monta filter, **nunca** confiar em filtro do front.

## H. Métricas obrigatórias

- p95 latência < 100ms
- Taxa de "no results" < 10%
- Taxa de click-through > 30%
- Sync lag p99 < 5min
- Tamanho do índice (alertar se cresce > 20%/mês inesperado)

## I. Greps

```bash
# Search sem debounce
rg -n "onChange.*search|onChange.*query" --type tsx | rg -v "debounce"

# Busca sem tenant_id (cross-tenant leak)
rg -n "index\.search\(" --type ts | rg -v "tenant"

# Engine como source of truth (anti-pattern)
rg -n "(index|client)\.addDocument" --type ts -B 2 | rg -v "(db\.|prisma\.|repo\.)"

# Highlight sem sanitize (XSS)
rg -n "_formatted" --type tsx -B 2 | rg "dangerouslySetInnerHTML" | rg -v "sanitize|DOMPurify"
```

## Output em sec.html

```
┌─ Search Quality (Módulo 10) ─────────────────────────────┐
│ Engine                       : Meilisearch ✅             │
│ Read-model do banco          : ✅ (fonte = Postgres)      │
│ Relevância com pesos         : ✅ ranking rules           │
│ Sinônimos                    : 47 configurados            │
│ Stop words pt-BR             : ✅                          │
│ Debounce 300ms               : ✅                          │
│ Min 2 chars                  : ✅                          │
│ Highlight + sanitize         : ✅                          │
│ Empty state com sugestões    : ✅                          │
│ Search history (localStorage): ✅                          │
│ Facetas configuradas         : 4 (cat/price/tags/status)  │
│ Tenant isolation no search   : ✅ (testes provam)         │
│ Sync incremental             : ✅ via fila                │
│ Reconciliação diária         : ✅ cron 3am                │
│ p95 latência                 : 47ms ✅                    │
│ Taxa no-results              : 6.2% ✅                    │
│ Status                       : ✅ DISCOVERABLE            │
└───────────────────────────────────────────────────────────┘
```

## Anti-padrões

- ❌ Engine como source of truth
- ❌ Busca sem `tenant_id` em multi-tenant
- ❌ Sem debounce (request a cada tecla)
- ❌ Tela em branco quando 0 resultados
- ❌ Highlight com `dangerouslySetInnerHTML` sem sanitize (XSS)
- ❌ Indexação síncrona no request (latência horrível)
- ❌ Sem reconciliação (drift silencioso entre banco e índice)
- ❌ Sinônimos hardcoded em código (configurar no engine)
- ❌ Sem `aria-busy` durante busca (a11y quebra screen reader)
- ❌ `LIKE '%q%'` em produção em tabela > 100k rows (DoS por queries lentas)
