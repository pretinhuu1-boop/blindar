---
name: graphql
category: api
module: 4
priority: P2
description: |
  GraphQL profundo (Apollo Federation, subscriptions, persisted queries,
  DataLoader, depth/complexity limits, field-level auth). Resolve
  problemas de GraphQL em escala: N+1 silencioso, queries maliciosas,
  schema fragmentado entre teams.
---

# Agent: graphql

## Missão

GraphQL bem feito desacopla equipes. Mal feito vira N+1 silencioso e
DoS trivial. Este agente prescreve patterns pra GraphQL em escala.

## Quando rodar

- Módulo 4 selecionado
- Detectado: `apollo-server`, `@apollo/federation`, `graphql-yoga`, `mercurius`
- Operador pediu "GraphQL", "Federation"

## A. Persisted queries (anti-DoS)

```ts
// Em prod, NUNCA aceitar query crua do client
const persistedQueries = await loadQueriesFromBuild();

if (process.env.NODE_ENV === 'production') {
  app.use('/graphql', (req, res, next) => {
    const hash = req.body.extensions?.persistedQuery?.sha256Hash;
    if (!hash || !persistedQueries[hash]) return res.status(400).send('Unknown query');
    req.body.query = persistedQueries[hash];
    next();
  });
}
```

Client envia só hash. Atacante não pode mandar query custom.

## B. Depth limit + complexity

```ts
import depthLimit from 'graphql-depth-limit';
import { createComplexityLimitRule } from 'graphql-validation-complexity';

const server = new ApolloServer({
  validationRules: [
    depthLimit(7),                                       // máx 7 níveis
    createComplexityLimitRule(1000, {                    // máx 1000 pontos
      scalarCost: 1, objectCost: 10, listFactor: 20,
    }),
  ],
});
```

Sem limit, query `users { posts { comments { author { posts { ... } } } } }`
explode em produção.

## C. DataLoader (N+1 fix)

```ts
const userLoader = new DataLoader(async (ids: string[]) => {
  const users = await db.user.findMany({ where: { id: { in: ids } } });
  return ids.map(id => users.find(u => u.id === id));
});

// Em vez de N queries (1 por post):
// resolveAuthor: post => db.user.findUnique({ where: { id: post.userId } })

// Coalesce todas chamadas em 1 query:
const resolvers = {
  Post: { author: (post, _, { dataloaders }) => dataloaders.user.load(post.userId) },
};
```

Sem DataLoader, 100 posts = 101 queries (N+1).

## D. Field-level auth

```ts
const resolvers = {
  User: {
    email: (user, _, { currentUser }) => {
      if (currentUser.id !== user.id && currentUser.role !== 'ADMIN') return null;
      return user.email;
    },
    salary: (user, _, { currentUser }) => {
      if (!can(currentUser, 'salary.read', user)) throw new ForbiddenError();
      return user.salary;
    },
  },
};
```

Lib: `graphql-shield`, `graphql-armor`.

## E. Subscriptions (real-time)

```ts
const resolvers = {
  Subscription: {
    appointmentCreated: {
      subscribe: (_, { tenantId }, { user }) => {
        if (user.tenantId !== tenantId) throw new ForbiddenError();
        return pubsub.asyncIterator(`apt:tenant:${tenantId}`);
      },
    },
  },
};
```

Pub/sub backend: Redis pra scale-out.

## F. Apollo Federation (multi-team)

Cada team tem seu subgraph:

```graphql
# Users service
type User @key(fields: "id") {
  id: ID!
  name: String!
  email: String!
}

# Appointments service
extend type User @key(fields: "id") {
  id: ID! @external
  appointments: [Appointment!]!
}
```

Apollo Router compõe. Cada team deploy independente.

## G. Schema versioning

GraphQL não versiona por path. Versiona por evolution:

- Adicionar campo = OK (não-breaking)
- Mudar tipo = BREAKING — usar `@deprecated`
- Remover campo deprecated > 6 meses sem uso

```graphql
type User {
  email: String!
  emailAddress: String! @deprecated(reason: "Use 'email'. Removed in 2026-12-01.")
}
```

Monitor: quem ainda usa campo deprecated.

## H. Error handling

GraphQL retorna `errors[]` no body com status 200. NÃO confundir com REST.

```ts
throw new GraphQLError('Invalid CPF', {
  extensions: { code: 'INVALID_INPUT', field: 'cpf', http: { status: 400 } }
});
```

## I. Tracing (Apollo Studio / OpenTelemetry)

Cada resolver tem trace. Identifica resolvers slow.

## J. Greps

```bash
# Resolver sem DataLoader (potencial N+1)
rg -n "resolvers = \\{" --type ts -A 50 | rg "db\\.|prisma\\." | wc -l
# Se > 10, suspeito

# Aceita query crua em prod (DoS risk)
rg -n "Apollo Server|createYoga" --type ts -A 20 | rg -v "persisted"

# Sem depth limit
rg -n "validationRules" --type ts | rg -v "depthLimit"
```

## Output em sec.html

```
┌─ GraphQL (Módulo 4) ─────────────────────────────────────┐
│ Persisted queries em prod      : ✅                       │
│ Depth limit                    : 7 ✅                     │
│ Complexity limit               : 1000 ✅                  │
│ DataLoader em N+1 potenciais   : ✅ 23 loaders            │
│ Field-level auth               : ✅ graphql-shield        │
│ Subscriptions com tenant scope : ✅                       │
│ Federation                     : ✅ 4 subgraphs           │
│ Deprecation timeline           : ✅ 6 meses               │
│ Tracing per resolver           : ✅ Apollo Studio         │
│ Schema breaking change check   : ✅ CI                    │
│ Status                         : ✅ GRAPHQL-PROD-READY   │
└───────────────────────────────────────────────────────────┘
```

## Anti-padrões

- ❌ Aceitar query crua em prod (DoS trivial)
- ❌ Sem depth/complexity limit
- ❌ Resolvers sem DataLoader (N+1 silencioso)
- ❌ Auth só no endpoint (campos individuais expostos)
- ❌ Subscriptions sem filter de tenant (broadcast leak)
- ❌ Federation sem schema check em CI
- ❌ Remover campo sem `@deprecated` timeline
- ❌ Stack trace no `errors[]` em prod
- ❌ Sem tracing (resolver slow invisível)
- ❌ Versionar GraphQL com `/v2/` (não é REST)
- ❌ Mutation com side effects retornando void (sem rastro)
