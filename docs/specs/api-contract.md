# Spec: API contract enforcement (item #3 do ROADMAP)

> Validar request/response contra OpenAPI/JSON Schema em runtime.
> Pega bugs que escapam de testes unitários.

## Problema

Teste unitário cobre **caso esperado**. Em runtime, cliente manda:
- Campo extra (`{"name": "x", "admin": true}` em endpoint que ignora `admin`)
- Tipo errado (`{"qty": "5"}` quando esperava number)
- Campo missing (`{"name": "x"}` sem `qty` obrigatório → server crash ou default suspeito)
- Estrutura aninhada inesperada

Sem contract enforcement, esses passam silenciosamente até virarem bug.

## Solução proposta: agente `api-contract.md`

### Padrões cobertos

1. **OpenAPI/Swagger** definido mas não enforced em runtime
2. **GraphQL schema** com resolvers que não validam input depth/cost
3. **Endpoints sem schema** documentado (input é black box)
4. **Response schema** que vaza campo sensível em condição rara
   (admin true só em algumas respostas)
5. **Versionamento de API** sem deprecation policy

### Defesas

- **Request validation middleware** que rejeita 400 se request
  não bate schema
- **Response validation** em dev/staging (logs em prod) que pega
  resposta divergente
- **Strict mode** no parser JSON: `additionalProperties: false`
  em endpoints sensíveis
- **GraphQL**: max depth, max complexity, persisted queries em prod

### Stack-específico

| Stack | Ferramenta sugerida |
|---|---|
| Node/Express | `ajv` + `express-openapi-validator` |
| Node/Fastify | nativo (`schema` em route) |
| Python/FastAPI | nativo (Pydantic) |
| Python/Flask | `flask-pydantic` ou `apispec` |
| Go | `ozzo-validation` ou `go-playground/validator` |
| Rust/Axum | `serde` + `validator` |

## Prompt (pra futuro agent)

```
Audit API contract enforcement:

1. OpenAPI/GraphQL schema documentado? Versionado?
2. Request validation existe (middleware OU per-route)?
3. Strict mode: additionalProperties: false em endpoints sensíveis?
4. Response validation em dev/staging?
5. Deprecation policy de versões antigas?
6. GraphQL: max depth, max complexity, persisted queries?
7. Erros de validation retornam payload util (não vazam estrutura interna)?

Implement (≤80 LOC):
1. Adicionar middleware de request validation
2. Habilitar additionalProperties:false em N endpoints sensíveis
3. Logar response divergente em staging
4. Test: request com campo extra → 400; campo missing → 400 com mensagem clara
5. Grep estático: endpoint novo sem schema declarado falha CI
```

## Mapeamento de frameworks

- OWASP ASVS V13 (API and Web Services)
- ISO 27001 A.14.2.1 (Secure development policy)
- NIST CSF PR.DS-7 (Dev environment separated)

## Por que não implementei agora

1. **Stack-específico demais** — agente útil precisa conhecer
   ferramenta da stack. Adicionar todas as tabelas vira manutenção.
2. **Sobreposição com `security.md`** atual (que já cobre
   input validation). Precisa decidir: agente próprio OU seção
   expandida em security.md?
3. **Risk de over-engineering**: nem todo projeto precisa de
   contract enforcement strict. Skill default ligado seria
   imposição.

## Quando faz sentido implementar

- API pública com >5 consumidores externos
- Microservices com contrato entre serviços
- Compliance (PCI exige contract enforcement em alguns casos)
