---
name: testing-strategy
category: quality
module: 11
priority: P0
description: |
  Vai além de E2E (functional-e2e). Cobre estratégia completa: unit tests
  com coverage gate, integration tests com DB real (não mock — feedback
  do user), contract tests (Pact) entre serviços, mutation testing
  (Stryker) pra medir QUALIDADE dos testes (não só cobertura), property-
  based testing (fast-check) pra invariantes, snapshot regression
  controlado, performance tests (k6) como gate.
---

# Agent: testing-strategy

## Missão

Cobertura 100% com testes ruins é mentira. Testes que mockam tudo passam
mesmo com bug. Este agente prescreve **estratégia em camadas** que pega
bug onde ele aparece, com qualidade mensurada.

## Quando rodar

- Módulo 11 selecionado (sempre — mandatory)
- Complementa `functional-e2e` (E2E + cada botão funcionando)

## A. Pirâmide de testes (proporção saudável)

```
        /\
       /E2\           ← 10%  — Playwright (functional-e2e cobre)
      /----\
     /Integ.\         ← 30%  — DB real, services reais
    /--------\
   /  Unit    \       ← 60%  — funções puras, business logic
  /____________\
```

**NÃO** ice cream cone invertido (muito E2E, pouco unit) — slow + flaky.

## B. Unit tests — regras

```ts
// vitest / jest
import { describe, test, expect } from 'vitest';
import { calculateCommission } from './commission';

describe('calculateCommission', () => {
  test('happy path: 20% padrão', () => {
    expect(calculateCommission(10000, { rate: 0.2 })).toBe(2000);
  });

  test('edge: amount zero', () => {
    expect(calculateCommission(0, { rate: 0.2 })).toBe(0);
  });

  test('attack: rate negativo lança', () => {
    expect(() => calculateCommission(100, { rate: -0.1 })).toThrow();
  });
});
```

### Regras

- 3+ asserts: happy + edge + attack (consistent com blindar PR rules)
- **Função pura preferível** (sem mocking complexo)
- **AAA pattern**: Arrange / Act / Assert
- Test name descritivo, **não** `test('it works')`
- Mock SÓ borders (HTTP externo, time) — não dependência interna

## C. Integration tests — com DB real

```ts
// SETUP: spinning up DB testcontainer
import { PostgreSqlContainer } from '@testcontainers/postgresql';

let container, prisma;

beforeAll(async () => {
  container = await new PostgreSqlContainer().start();
  prisma = new PrismaClient({ datasources: { db: { url: container.getConnectionUri() } } });
  await prisma.$executeRawUnsafe(await readFile('schema.sql', 'utf8'));
}, 60_000);

afterAll(async () => {
  await prisma.$disconnect();
  await container.stop();
});

// TEST: service real, DB real, zero mock
test('createAppointment cria + dispara webhook + log audit', async () => {
  const user = await createUserFixture();
  const apt = await appointmentService.create({ userId: user.id, /* ... */ });

  expect(apt.id).toBeTruthy();
  expect(await prisma.auditLog.count()).toBe(1);
  expect(webhookSpy).toHaveBeenCalledWith(expect.objectContaining({ type: 'apt.created' }));
});
```

### Por que DB real (não SQLite/mock)

- Postgres-specific bugs (RLS, JSONB, constraints) só aparecem em Postgres
- Migration roda nos testes (drift detection)
- Transactions reais (rollback funciona)
- Performance characteristics próximas à prod

### Faster: shared DB com transaction rollback

```ts
beforeEach(async () => { await prisma.$executeRaw`BEGIN`; });
afterEach(async () => { await prisma.$executeRaw`ROLLBACK`; });
```

## D. Contract tests (Pact)

Quando frontend e backend são deploys separados → contrato pode quebrar
silenciosamente.

```ts
// Consumer (frontend)
const pact = new Pact({ consumer: 'web', provider: 'api' });

await pact.addInteraction({
  state: 'has user with id abc',
  uponReceiving: 'a request for user abc',
  withRequest: { method: 'GET', path: '/users/abc' },
  willRespondWith: {
    status: 200,
    body: { id: like('abc'), email: like('test@test.com') }
  }
});

// Pacto publicado em Pact Broker
// Provider (backend) verifica antes de deploy
pact-verifier --provider-base-url=http://localhost:3000 --pact-broker-url=...
```

Quebrou contrato → build vermelho antes de chegar em prod.

## E. Mutation testing (Stryker)

Mede **qualidade** dos testes — não só cobertura.

```bash
npx stryker run
```

Stryker muda o código (operadores, return values) e roda os testes:
- **Killed**: teste pegou a mutation (bom)
- **Survived**: mutation passou (teste fraco/inútil)

### Meta

- Mutation score > **80%**
- Sobreviventes = revisar (faltam asserts? teste só checa "não throw"?)

### Anti-pattern típico que Stryker pega

```ts
// Test
test('soma', () => { expect(sum(2,3)).toBeTypeOf('number'); });
// Bug: sum retorna sempre 0 → teste PASSA mas é inútil
// Stryker muda `return a+b` pra `return a-b` → teste continua passando = survived
```

## F. Property-based testing (fast-check)

Pra invariantes que devem valer pra TODOS inputs.

```ts
import fc from 'fast-check';

test('round-trip JSON parse/stringify preserva conteúdo', () => {
  fc.assert(fc.property(fc.jsonValue(), (value) => {
    expect(JSON.parse(JSON.stringify(value))).toEqual(value);
  }));
});

test('cents → BRL → cents é idempotente', () => {
  fc.assert(fc.property(fc.bigInt({ min: 0n, max: 100_000_000n }), (cents) => {
    const brl = centsToBrl(cents);
    expect(brlToCents(brl)).toBe(cents);
  }));
});
```

Útil pra: parsers, conversões, validações, formatters, ordenação.

## G. Snapshot tests (controlados)

```ts
test('renders dashboard correctly', () => {
  const { container } = render(<Dashboard />);
  expect(container).toMatchSnapshot();
});
```

### Regras

- Snapshots em **componentes estáveis** (não muda toda semana)
- **Pequenos** (não snapshot de página inteira)
- **Inline snapshot** (`.toMatchInlineSnapshot()`) pra fácil revisar
- Revisar diff toda vez que snapshot muda — não fazer `--update-snapshot` cego

## H. Performance tests (k6)

```js
// load.k6.js
import http from 'k6/http';
import { check } from 'k6';

export const options = {
  scenarios: {
    ramping: {
      executor: 'ramping-vus',
      stages: [
        { duration: '1m', target: 100 },
        { duration: '3m', target: 500 },
        { duration: '1m', target: 0 }
      ]
    }
  },
  thresholds: {
    http_req_duration: ['p(95)<500'],     // 95% < 500ms
    http_req_failed: ['rate<0.01']         // < 1% errors
  }
};

export default function() {
  const res = http.get('https://api.example.com/appointments');
  check(res, { 'status 200': r => r.status === 200 });
}
```

Rodar em CI antes de release. Falha = não sobe.

## I. Coverage gates

```yaml
# vitest.config.ts
coverage: {
  provider: 'v8',
  thresholds: {
    statements: 80,
    branches: 75,
    functions: 80,
    lines: 80
  },
  exclude: ['**/*.config.*', '**/types/**', '**/mocks/**']
}
```

**Atenção**: coverage NÃO é meta primária. **Mutation score** é melhor sinal.
Coverage 80% com mutation 30% = testes ruins.

## J. Flake detection

Test flaky (passa às vezes) = perda de confiança no CI.

```bash
# Roda suite 5x, falha se algum teste passou às vezes
npm test -- --reporter junit --run-count 5
```

Tools: **Buildkite Test Analytics**, **CircleCI Test Insights** detectam
flaky automático e quarentenam.

## K. Test fixtures consistentes

```ts
// test/fixtures/factory.ts
import { Factory } from 'fishery';

export const userFactory = Factory.define<User>(({ sequence }) => ({
  id: randomUUID(),
  email: `user-${sequence}@test.com`,
  role: 'OPERACIONAL',
  tenantId: randomUUID(),
  createdAt: new Date('2026-01-01')
}));

// Uso:
const admin = userFactory.build({ role: 'ADMIN' });
const tenant = await createTenant();
const users = userFactory.buildList(10, { tenantId: tenant.id });
```

Reusa em todos os testes — mudança no schema atualiza tudo.

## L. Mock só nas bordas

```
✅ Mock: HTTP externo (Stripe API, OpenAI, sendgrid)
✅ Mock: time (vi.setSystemTime, jest.useFakeTimers)
✅ Mock: random (seed determinístico)

❌ Mock: DB (use container real)
❌ Mock: outro service interno (use real ou contract test)
❌ Mock: tudo (vira teste de mock, não de código)
```

## Output esperado em sec.html

```
┌─ Testing Strategy (Módulo 11) ───────────────────────────┐
│ Unit tests                    : 1247 ✅                    │
│ Integration tests (DB real)   : 89 ✅                      │
│ E2E (functional-e2e)          : 47 ✅                      │
│ Contract tests (Pact)         : ✅ FE↔BE green            │
│ Statement coverage            : 84% ✅ (gate 80%)         │
│ Branch coverage               : 78% ✅ (gate 75%)         │
│ Mutation score (Stryker)      : 83% ✅ (meta 80%)         │
│ Property-based (fast-check)   : 23 invariantes            │
│ Snapshot tests                : 142 estáveis              │
│ Performance test (k6)         : p95 245ms ✅ (gate 500ms) │
│ Flaky rate                    : 0.1% ✅                    │
│ CI tempo total                : 4min12s ✅                │
│ Status                        : ✅ COMPREHENSIVE          │
└───────────────────────────────────────────────────────────┘
```

## Anti-padrões

- ❌ Mockar tudo (teste passa, prod quebra)
- ❌ Cobertura 100% sem mutation testing (mentira)
- ❌ E2E como único tipo de teste (slow + flaky)
- ❌ Test name "it works" / "test 1"
- ❌ Snapshot de página inteira (toda mudança visual quebra)
- ❌ `--update-snapshot` automático sem revisar diff
- ❌ Test que depende de outro test (ordem importa = bug)
- ❌ SQLite em test, Postgres em prod (drift)
- ❌ `setTimeout(done, 1000)` em test (use fake timers)
- ❌ Ignorar testes flaky em vez de investigar
- ❌ Sem coverage gate (regressão silenciosa)
- ❌ Sem performance test (descobre lentidão em prod)
