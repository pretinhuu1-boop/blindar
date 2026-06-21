---
name: vector-db-security
category: core
module: 2
priority: P0
description: |
  Avalia segurança de vector databases (chromadb, pinecone, weaviate,
  pgvector, qdrant, milvus): isolamento por tenant em embeddings, PII
  em vectors, leak via similarity search, namespace pollution, access
  control, encryption at rest, injection via metadata filter. Bug aqui
  vaza dado de um cliente pro outro via "busca semântica". Skipped se
  projeto não usa vector DB.
---

# Agent: vector-db-security

## Missão

Vector DB é blind spot de segurança. Time blinda Postgres com RLS, mas
deixa Pinecone aberto com namespace = "default" pra todos os tenants. Bug
clássico: usuário do tenant A pergunta "qual o salário do CEO?" e
similarity search retorna chunk indexado pelo tenant B porque o filter
de metadata foi esquecido. Este agente **trata vector store como
banco** — RLS, encryption, audit, tenant isolation.

## Quando rodar

- Módulo 2 selecionado (priority P0 — quebra de tenant é CRIT)
- Detecção: lib de vector DB presente
- Operador pediu "isolamento", "tenant", "multi-tenancy", "embeddings"

## A. Detecção de vector DB

```bash
# Libs
rg -l "chromadb|pinecone|weaviate|qdrant|milvus|pgvector|@pinecone-database|@qdrant/js-client" \
  --type py --type ts --type js

# Operações sensíveis
rg -n "\.upsert\(|\.query\(|\.search\(|similarity_search|as_retriever"

# Schemas
rg -n "create_collection|createCollection|create_index|createIndex" --type py --type ts
```

Sem hit: **skipped**.

## B. Tenant isolation patterns

### B.1 Namespace (Pinecone, Qdrant)

```python
# ❌ ERRADO — todos tenants no mesmo namespace
index.upsert(vectors=[(id, vec, meta)])
results = index.query(vector=query_vec, top_k=5)

# ✅ CORRETO — namespace por tenant
index.upsert(vectors=[(id, vec, meta)], namespace=f"tenant_{tenant_id}")
results = index.query(vector=query_vec, top_k=5, namespace=f"tenant_{tenant_id}")
```

### B.2 Metadata filter (ChromaDB, Weaviate, pgvector)

```python
# ❌ ERRADO — sem filter
results = collection.query(query_embeddings=[q], n_results=5)

# ✅ CORRETO — filter obrigatório
results = collection.query(
    query_embeddings=[q],
    n_results=5,
    where={"tenant_id": current_tenant_id}  # NUNCA opcional
)
```

### B.3 pgvector + RLS

```sql
-- ✅ Tabela com RLS
CREATE TABLE doc_embeddings (
  id UUID PRIMARY KEY,
  tenant_id UUID NOT NULL,
  content TEXT,
  embedding VECTOR(1536),
  metadata JSONB
);

ALTER TABLE doc_embeddings ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON doc_embeddings
  USING (tenant_id = current_setting('app.current_tenant')::uuid);

CREATE INDEX ON doc_embeddings USING ivfflat (embedding vector_cosine_ops)
  WHERE tenant_id IS NOT NULL;
```

**Vantagem pgvector:** RLS do Postgres aplica automático em similarity
search. Não tem como esquecer filter.

### B.4 Cluster/index separado (high-security)

Cliente enterprise paga por isolamento físico:
- Pinecone: index dedicado por tenant
- Qdrant: collection dedicada
- Weaviate: classe dedicada ou shard

Trade-off: custo alto, mas zero risco de cross-tenant leak.

## C. PII em embeddings (CRIT)

Embeddings **NÃO** são anonimização. Modelo recente (vec2text, GEIA)
**inverte embedding → texto original** com 92% accuracy. Tratar embedding
como o próprio texto: criptografia at rest, RLS, audit.

```python
# ❌ ERRADO — indexar CPF, email, telefone direto
for doc in patients:
    text = f"Paciente {doc.cpf} {doc.name} {doc.email} {doc.diagnosis}"
    vec = embed(text)
    collection.upsert(id=doc.id, vector=vec)

# ✅ CORRETO — scrub PII antes de embed
def sanitize(text):
    text = re.sub(r"\d{3}\.?\d{3}\.?\d{3}-?\d{2}", "[CPF]", text)  # CPF
    text = re.sub(r"\d{2}\.?\d{3}\.?\d{3}-?\d", "[RG]", text)
    text = re.sub(r"[\w.-]+@[\w.-]+\.\w+", "[EMAIL]", text)
    text = re.sub(r"\(?\d{2}\)?\s?9?\d{4}-?\d{4}", "[PHONE]", text)
    return text

for doc in patients:
    safe = sanitize(doc.diagnosis)
    vec = embed(safe)
    collection.upsert(
        id=doc.id, vector=vec,
        metadata={"tenant_id": doc.tenant_id, "patient_id_hash": hash(doc.id)}
    )
```

## D. Encryption at rest

| Provider | Default | Recomendado |
|---|---|---|
| Pinecone | AES-256 server-side | + CMK no plano enterprise |
| pgvector | depende do Postgres | TDE + pgcrypto em colunas sensíveis |
| Qdrant Cloud | AES-256 | + private link |
| Weaviate Cloud | AES-256 | + BYOK |
| ChromaDB self-hosted | nenhum por default | LUKS no disco + secrets vault |
| Milvus | nenhum por default | Provisionar TLS + encrypted volume |

**Grep:**
```bash
# Self-hosted Chroma/Milvus sem encryption — CRIT
rg -n "chromadb.PersistentClient|Milvus\(" --type py
# Verificar se path está em volume criptografado
```

## E. Access control

```python
# ❌ API key compartilhada client-side (frontend)
PINECONE_API_KEY = "pk_live_..."  # vazado no bundle JS

# ✅ Backend proxy — frontend nunca toca vector DB
@router.post("/search")
async def search(query: str, user: User = Depends(auth)):
    results = pinecone_index.query(
        vector=embed(query),
        top_k=5,
        namespace=f"tenant_{user.tenant_id}",  # forçado server-side
        filter={"acl_role": {"$in": user.roles}}
    )
    return results
```

**Grep:**
```bash
# API key de vector DB em frontend
rg -n "PINECONE_API_KEY|QDRANT_API_KEY|WEAVIATE_API_KEY" \
  --type ts --type js --type tsx -g '!**/server/**' -g '!**/api/**'

# Vector DB call direto do client
rg -n "PineconeClient\(|new Pinecone\(|chromadb\." \
  --type ts --type tsx -g '!**/server/**' -g '!**/api/**'
```

## F. Metadata filter injection

Metadata filter recebe input do user → injection possível.

```python
# ❌ VULNERÁVEL — user controla filter
@router.post("/search")
def search(query: str, filter_dict: dict):  # ← user envia filter
    return index.query(vector=embed(query), filter=filter_dict)
# User envia {"tenant_id": {"$ne": "outro-tenant"}} → bypass

# ✅ SEGURO — whitelist de filters, tenant_id forçado
def search(query: str, category: str | None, user=Depends(auth)):
    safe_filter = {"tenant_id": user.tenant_id}  # forçado
    if category in ALLOWED_CATEGORIES:
        safe_filter["category"] = category
    return index.query(vector=embed(query), filter=safe_filter)
```

## G. Audit log

Toda query/upsert/delete em vector store deve ir pra audit log:

```
{
  "ts": "2026-06-21T10:30:00Z",
  "tenant_id": "uuid",
  "user_id": "uuid",
  "action": "vector.query",
  "namespace": "tenant_xxx",
  "filter_applied": {"tenant_id": "..."},
  "top_k": 5,
  "result_ids": ["id1", "id2"]
}
```

LGPD: dado retornado de busca é processamento → registrar.

## H. Greps obrigatórios

```bash
# Query sem filter/namespace (CRIT)
rg -n "\.query\(" --type py -A 3 | grep -v "filter\|namespace\|where"

# Upsert sem tenant_id no metadata
rg -n "\.upsert\(" --type py -A 5 | grep -v "tenant_id\|namespace"

# CPF/email em texto indexado
rg -n "embed\(|embedding\(" --type py -B 2 | grep -i "cpf\|email\|phone\|telefone"

# Vector DB no frontend
rg -n "pinecone|chromadb|qdrant|weaviate" --type tsx --type jsx

# Self-hosted sem TLS
rg -n "http://.*:6333|http://.*:8080|http://.*:19530" --type py --type ts

# API key hardcoded
rg -n "pk_live_|api_key.*=.*['\"][a-zA-Z0-9_-]{20,}" --type py --type ts
```

## I. Output esperado em sec.html

```
┌─ Vector DB Security (Módulo 2) ──────────────────────────┐
│ Vector DB detectado          : pgvector ✅                │
│ Tenant isolation             : RLS Postgres ✅            │
│ Filter/namespace em queries  : 100% ✅ (12/12)            │
│ PII scrubbing pre-embed      : ✅ regex + Presidio        │
│ Encryption at rest           : TDE Postgres ✅            │
│ Vector DB acessado no client : 0 ✅                       │
│ API key vazada               : 0 ✅                       │
│ Audit log de queries         : ✅ → CloudWatch            │
│ Metadata filter injection    : 0 ✅ (whitelist)           │
│ Backup encrypted             : ✅                         │
│ Status                       : ✅ HARDENED                │
└───────────────────────────────────────────────────────────┘
```

## J. Anti-padrões (CRIT)

- ❌ Query sem namespace/filter de tenant_id
- ❌ Upsert sem tenant_id no metadata
- ❌ PII (CPF/email/telefone) embeddado sem scrub
- ❌ ChromaDB/Milvus self-hosted em disco não criptografado
- ❌ API key de vector DB no frontend
- ❌ User controla filter dict (metadata injection)
- ❌ Mesmo namespace default pra todos clientes
- ❌ Sem audit log de query/upsert
- ❌ Vector DB exposto na internet sem TLS
- ❌ Backup do vector store sem encryption
- ❌ Delete user → embeddings persistem (LGPD violation)
- ❌ Sem rate limit em endpoint de search (DoS via embedding cost)

## K. Interação com outros agentes

- **rag-quality**: chunking/retrieval — qualidade separada de segurança
- **secrets-management**: API keys de vector DB
- **lgpd**: scrub PII + right to be forgotten cascade
- **rbac**: ACL via metadata filter
- **db-architect**: pgvector + RLS é decisão híbrida
- **observability-ai**: tracing de query latency e hit rate
