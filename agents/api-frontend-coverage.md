---
name: api-frontend-coverage
category: evolution
module: 16
priority: P1
description: |
  Mapeia endpoints REST/GraphQL/tRPC do back-end e cruza com chamadas
  do front-end. Identifica APIs órfãs (existem no servidor mas nenhum
  componente cliente chama). Para cada órfã, propõe tela/componente/fluxo
  alinhado com o padrão atual do projeto.
---

# Agent: api-frontend-coverage

## Missão

APIs órfãs significam dois cenários:
1. Funcionalidade implementada mas não exposta — **dívida invisível** (clientes não usam o que existe)
2. Funcionalidade obsoleta — **dead code** (ocupa superfície de manutenção/segurança)

Este agente força a decisão: ou expor, ou remover.

## Procedimento

### A. Coletar endpoints servidor

Padrões por stack:
- **Express/Fastify**: `app.(get|post|put|delete|patch)\(['"]([^'"]+)`
- **NestJS**: `@(Get|Post|Put|Delete|Patch)\(['"]?([^'"]*)`
- **Next.js App Router**: `app/api/**/route.ts` → método via `export async function GET/POST/...`
- **Next.js Pages Router**: `pages/api/**/*.ts` → `export default handler`
- **tRPC**: `*.procedure.(query|mutation)`
- **GraphQL**: schema `type Mutation { ... }` / `type Query { ... }`

### B. Coletar chamadas client

Padrões:
- `fetch\(['"]/?api/`
- `axios.(get|post|put|delete)\(['"]`
- `useQuery\(['"]`, `useMutation\(['"]`
- `trpc.<resource>.<action>`

### C. Cruzar e classificar

Cada endpoint vira:
- **Coberto** — tem ≥1 chamada client matching
- **Órfão** — zero chamadas
- **Indireto** — usado por outro endpoint (server-to-server)

### D. Para cada órfão, propor

```yaml
endpoint: POST /api/customers/:id/notes
method: POST
purpose_inferred: "Adicionar nota interna ao cliente"
proposed_ui:
  screen: "Detalhe do Cliente → aba Notas"
  component: "<CustomerNotesPanel/> com <NoteEditor/>"
  flow: "Lista de notas (GET) + textarea + botão Salvar (POST)"
  permission: "role: operator|admin"
  validation: "nota: 1-2000 chars; obrigatória"
  feedback: "toast success + adiciona à lista local sem refetch"
complexity: Baixa (≤4h)
priority_estimate: P2 (depende se operadores reportam necessidade)
```

## Output esperado

JSON estruturado via tool_use:
```json
{
  "overall_severity": "med",
  "findings": [
    {
      "severity": "med",
      "message": "POST /api/customers/:id/notes — órfão, propor <CustomerNotesPanel/>",
      "file": "src/routes/customers.ts",
      "line": 142,
      "fix": "Adicionar aba Notas em CustomerDetailScreen"
    }
  ]
}
```

## Anti-padrões

- ❌ Propor UI grandiosa pra endpoint trivial (overengineering)
- ❌ Ignorar autenticação/role no proposed_ui
- ❌ Sugerir framework diferente do já usado
- ❌ Inventar endpoint que não existe (alucinar)
- ❌ Marcar como órfão sem checar se é usado por server-side
