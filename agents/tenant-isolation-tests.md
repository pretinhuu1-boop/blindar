---
name: tenant-isolation-tests
category: security
module: 2
priority: P0
description: |
  Multi-tenant sem testes explícitos de isolamento é uma bomba relógio.
  Este agente gera testes automatizados que PROVAM: tenant A não vê
  dados de tenant B, OPERACIONAL não vê dados de outros OPERACIONAIS,
  cache não vaza entre tenants, ID enumeration retorna 404 (não 403),
  RLS Postgres está ativo em todas as tabelas. Bloqueia release se
  qualquer teste falhar.
---

# Agent: tenant-isolation-tests

## Missão

Tenant leak = perda de confiança total. Pior que crit normal: não dá pra
arrumar com hotfix (dados já foram vistos). Este agente garante testes
explícitos que rodam em CI provando isolamento.

## Quando rodar

- Módulo 2 selecionado
- Detectado: `tenantId` ou `tenant_id` em schema/código
- `project_type ∈ {saas, ecom}` ou multi-tenant declarado

## A. Matriz de isolamento (o que precisa ser testado)

| Dimensão | Caso |
|---|---|
| **Tenant** | Tenant A não vê NADA de Tenant B (read, write, delete, count) |
| **User scope (OPERACIONAL)** | User X do tenant A não vê dados de User Y do tenant A |
| **Role** | OPERACIONAL não acessa endpoint de ADMIN |
| **API key / token** | Token do tenant A não funciona em tenant B |
| **Cache** | Cache key não colide entre tenants |
| **Storage** | URL de upload do tenant A não acessível por B |
| **Job/queue** | Worker processando job do tenant A não acessa B no contexto |
| **WebSocket room** | Tenant A não recebe broadcast de tenant B |
| **Logs/audit** | Audit log filtrado por tenant_id correto |
| **Backup/restore** | Restore parcial não mistura tenants |

## B. Test fixture obrigatório

```ts
// test/setup/isolation-fixtures.ts
export async function setupTwoTenants() {
  const tenantA = await db.tenant.create({ data: { name: 'Tenant A', slug: 'a' } });
  const tenantB = await db.tenant.create({ data: { name: 'Tenant B', slug: 'b' } });

  const userA = await createUser({ tenantId: tenantA.id, role: 'ADMIN', email: 'a@test' });
  const userB = await createUser({ tenantId: tenantB.id, role: 'ADMIN', email: 'b@test' });
  const opA = await createUser({ tenantId: tenantA.id, role: 'OPERACIONAL', email: 'opa@test' });
  const opB = await createUser({ tenantId: tenantB.id, role: 'OPERACIONAL', email: 'opb@test' });

  const aptA = await createAppointment({ tenantId: tenantA.id, assignedToId: opA.id });
  const aptB = await createAppointment({ tenantId: tenantB.id, assignedToId: opB.id });

  return { tenantA, tenantB, userA, userB, opA, opB, aptA, aptB };
}
```

## C. Testes que blindar gera automaticamente

```ts
import { describe, test, expect } from 'vitest';
import { setupTwoTenants, tokenFor } from './setup';

describe('Tenant Isolation', () => {
  test('READ: Tenant A não lista appointments de B', async () => {
    const { userA, aptB } = await setupTwoTenants();
    const res = await api.get('/appointments').auth(tokenFor(userA));
    expect(res.status).toBe(200);
    expect(res.body.data.map(a => a.id)).not.toContain(aptB.id);
  });

  test('READ: Tenant A acessar /appointments/:id de B retorna 404 (NÃO 403)', async () => {
    const { userA, aptB } = await setupTwoTenants();
    const res = await api.get(`/appointments/${aptB.id}`).auth(tokenFor(userA));
    expect(res.status).toBe(404);   // 404 e NÃO 403 (403 confirma que ID existe!)
  });

  test('WRITE: Tenant A não consegue editar appointment de B', async () => {
    const { userA, aptB } = await setupTwoTenants();
    const res = await api.patch(`/appointments/${aptB.id}`)
      .send({ status: 'cancelled' }).auth(tokenFor(userA));
    expect(res.status).toBe(404);
    const apt = await db.appointment.findUnique({ where: { id: aptB.id } });
    expect(apt.status).not.toBe('cancelled');
  });

  test('DELETE: Tenant A não deleta dados de B', async () => {
    const { userA, aptB } = await setupTwoTenants();
    const res = await api.delete(`/appointments/${aptB.id}`).auth(tokenFor(userA));
    expect(res.status).toBe(404);
    expect(await db.appointment.findUnique({ where: { id: aptB.id } })).not.toBeNull();
  });

  test('COUNT: agregações não contam dados de outro tenant', async () => {
    const { userA, tenantA, tenantB } = await setupTwoTenants();
    await createAppointment({ tenantId: tenantB.id });  // adiciona em B
    const res = await api.get('/stats/appointments-count').auth(tokenFor(userA));
    expect(res.body.count).toBe(1);   // só de A
  });

  test('SEARCH/FILTER: filtros não vazam entre tenants', async () => {
    const { userA, aptB } = await setupTwoTenants();
    const res = await api.get(`/appointments?q=${aptB.title}`).auth(tokenFor(userA));
    expect(res.body.data).toEqual([]);
  });

  test('OPERACIONAL: só vê próprios dados (não de outro OPERACIONAL do mesmo tenant)', async () => {
    const { opA, tenantA } = await setupTwoTenants();
    const otherOp = await createUser({ tenantId: tenantA.id, role: 'OPERACIONAL' });
    const otherApt = await createAppointment({ tenantId: tenantA.id, assignedToId: otherOp.id });
    const res = await api.get('/appointments').auth(tokenFor(opA));
    expect(res.body.data.map(a => a.id)).not.toContain(otherApt.id);
  });

  test('ROLE: OPERACIONAL não acessa rota admin', async () => {
    const { opA } = await setupTwoTenants();
    const res = await api.get('/admin/users').auth(tokenFor(opA));
    expect(res.status).toBe(403);
  });

  test('TOKEN: token de tenant A não funciona em tenant B', async () => {
    const { userA, tenantB } = await setupTwoTenants();
    // user é ADMIN do A — não deveria virar admin do B via header
    const res = await api.get('/admin/users')
      .auth(tokenFor(userA))
      .set('X-Tenant-Id', tenantB.id);
    // ignora header, vai pelo claim do token
    const users = res.body.data;
    expect(users.every(u => u.tenantId === userA.tenantId)).toBe(true);
  });

  test('STORAGE: URL signed do tenant A não funciona se key contém B', async () => {
    const { userA, tenantB } = await setupTwoTenants();
    const res = await api.post('/uploads/sign')
      .send({ filename: '../tenant-b/secret.pdf' }).auth(tokenFor(userA));
    expect(res.body.key).not.toContain(`tenant-${tenantB.id}`);
    expect(res.body.key).toContain(`tenant-${userA.tenantId}`);
  });

  test('CACHE: chave não colide (tenant prefix obrigatório)', () => {
    const k1 = cacheKey('users', { tenantId: 'a' });
    const k2 = cacheKey('users', { tenantId: 'b' });
    expect(k1).not.toBe(k2);
    expect(k1).toMatch(/^tenant:a:/);
  });

  test('RLS: query crua sem SET tenant context falha ou retorna vazio', async () => {
    // Conexão sem SET LOCAL app.current_tenant
    await expect(db.$queryRaw`SELECT * FROM appointments`).rejects.toThrow();
    // OU retorna vazio (depende da policy default)
  });
});
```

## D. RLS verification

```sql
-- Test: RLS está habilitado em TODAS tabelas tenant-scoped
SELECT table_name,
       (SELECT relrowsecurity FROM pg_class WHERE relname = table_name) as rls_enabled
FROM information_schema.tables
WHERE table_schema = 'public'
  AND EXISTS (SELECT 1 FROM information_schema.columns
              WHERE table_name = tables.table_name AND column_name = 'tenant_id');
-- Esperado: rls_enabled = true em todas
```

Bloqueia release se alguma tabela com `tenant_id` tem `rls_enabled = false`.

## E. Fuzz / property-based de IDs (UUID enumeration)

```ts
test.concurrent('Fuzz: 1000 IDs aleatórios retornam 404 consistente', async () => {
  const { userA } = await setupTwoTenants();
  for (let i = 0; i < 1000; i++) {
    const fakeId = randomUUID();
    const res = await api.get(`/appointments/${fakeId}`).auth(tokenFor(userA));
    expect(res.status).toBe(404);
  }
});
```

## F. Cross-tenant cache poisoning

```ts
test('CACHE POISONING: tenant A não consegue popular cache com chave de B', async () => {
  const { userA, tenantB } = await setupTwoTenants();
  // Tenta forçar cache key específico via header malicioso
  const res = await api.get('/appointments').auth(tokenFor(userA))
    .set('X-Cache-Key', `tenant:${tenantB.id}:appointments`);
  // backend ignora header X-Cache-Key, usa tenantId do token
  expect(cache.has(`tenant:${tenantB.id}:appointments`)).toBe(false);
});
```

## G. WebSocket / SSE isolation

```ts
test('WS: tenant A não recebe broadcast de tenant B', async () => {
  const { userA, tenantB } = await setupTwoTenants();
  const ws = await connectWs(tokenFor(userA));
  const messages: any[] = [];
  ws.on('message', m => messages.push(JSON.parse(m)));

  // Servidor dispara em tenant B
  await broadcastToTenant(tenantB.id, { type: 'apt.created', data: {...} });
  await sleep(500);

  expect(messages).toEqual([]);
});
```

## H. Job/queue isolation

```ts
test('JOB: worker processa job mantendo tenant_id do payload', async () => {
  const { tenantA, tenantB } = await setupTwoTenants();
  await queue.add('send-email', { tenantId: tenantA.id, to: 'user@a.com' });

  const handler = await waitForJob('send-email');
  expect(handler.tenantId).toBe(tenantA.id);
  // queries dentro do handler usam SET LOCAL app.current_tenant = ?
});
```

## I. Audit log filtering

```ts
test('AUDIT: tenant A não vê audit log de B', async () => {
  const { userA, tenantB } = await setupTwoTenants();
  await db.auditLog.create({ data: { tenantId: tenantB.id, /* ... */ } });
  const res = await api.get('/admin/audit-log').auth(tokenFor(userA));
  expect(res.body.data.every(l => l.tenantId === userA.tenantId)).toBe(true);
});
```

## J. CI integration

```yaml
# .github/workflows/test.yml
- name: Tenant Isolation Tests
  run: npm test -- --filter tenant-isolation
  # FALHA = bloqueia merge
```

Bloqueia merge se **qualquer** teste de isolamento falhar.

## Output esperado em sec.html

```
┌─ Tenant Isolation Tests (Módulo 2) ──────────────────────┐
│ Testes gerados                : 47                         │
│ READ isolation                : ✅ 12 tests passing       │
│ WRITE isolation               : ✅ 8                       │
│ DELETE isolation              : ✅ 4                       │
│ COUNT/AGGREGATE               : ✅ 3                       │
│ FILTER/SEARCH                 : ✅ 5                       │
│ Role-scope (OPERACIONAL)      : ✅ 4                       │
│ Token reuse cross-tenant      : ✅ 2                       │
│ Storage path injection        : ✅ 3                       │
│ Cache key collision           : ✅ 2                       │
│ RLS habilitado todas tabelas  : ✅ 23/23                  │
│ WebSocket broadcast           : ✅ 2                       │
│ Job/queue context             : ✅ 2                       │
│ Audit log filter              : ✅ 1                       │
│ Fuzz UUID enumeration         : ✅ 1000/1000 → 404        │
│ Status                        : ✅ ISOLATED               │
└───────────────────────────────────────────────────────────┘
```

## Intelligence (⭐ v0.20) — não gerar teste pra tabela global

Consulta `db-architect.global_tables` em `.blindar/intelligence.yml`:

```yaml
tenant-isolation-tests:
  inherit_from: db-architect    # respeita global_tables do db-architect

  also_skip_tables:
    # Mesmo se db-architect não declarou
    - admin_audit_log             # acesso só MASTER
    - billing_invoices_master     # billing entre você e tenant

  skip_endpoints:
    # Endpoints que LEGITIMAMENTE não são tenant-scoped
    - "/admin/tenants"            # MASTER vê todos por design
    - "/admin/system/*"           # admin de plataforma
    - "/health/*"                 # endpoints públicos
    - "/api/public/*"             # API pública
    - "/api/webhooks/*"           # webhooks de gateway externo

  cross_tenant_intentional:
    # Casos onde MASTER PRECISA ver cross-tenant (com audit)
    - role: MASTER
      endpoints: ["/admin/users/search", "/admin/tenants/*"]
      audit_required: true        # sempre logado
```

### Auto-detecção

- Endpoint que tem `@Roles('MASTER')` exclusivamente → pula teste de cross-tenant
- Endpoint com path `/health`, `/metrics`, `/public/` → pula
- Tabela marcada `@blindar:global` no schema → pula

### Falso positivo evitado

Sem essa intelligence, tenant-isolation-tests gerava ~12 testes inúteis
em projeto médio (testando isolamento em `health_checks` e `feature_flags`),
poluindo CI e dando ruído.

## Anti-padrões

- ❌ Retornar 403 quando ID existe em outro tenant (confirma existência)
- ❌ Filtro de tenant só no controller (esquece de filtrar no service)
- ❌ Cache key sem prefix de tenant
- ❌ Job sem tenant_id no payload
- ❌ Broadcast WS sem filtro de room por tenant
- ❌ RLS desativado em alguma tabela tenant-scoped
- ❌ Endpoint admin acessível por OPERACIONAL
- ❌ Token de service-account com `*` em tenant (master key)
- ❌ Storage path com filename do user (`/uploads/${filename}`)
- ❌ Sem testes — "confio que tá certo"
