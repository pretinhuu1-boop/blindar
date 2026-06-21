#!/usr/bin/env bash
# Wrapper API: vector-db-security — isolamento tenant + PII em vector DB
BLINDAR_AGENT="check-vector-db-security"
source "$(dirname "$0")/_lib.sh"
source "$(dirname "$0")/_api_wrapper.sh"

log_section "Check: vector-db-security (segurança vector DB via Claude API)"

# Detecta vector DB
VDB_HIT=0
if command -v rg >/dev/null 2>&1; then
  if rg -l --type py --type ts --type js \
       "chromadb|pinecone|weaviate|qdrant|milvus|pgvector|@pinecone-database|@qdrant/js-client|weaviate-ts-client" \
       . >/dev/null 2>&1; then
    VDB_HIT=1
  fi
fi

if [ "$VDB_HIT" -eq 0 ]; then
  log_info "Nenhum vector DB detectado — skipped"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

# Coleta evidência
EVIDENCE=""
EVIDENCE+="=== Vector DB detection ===\nProjeto usa vector database.\n\n"

[ -f "package.json" ] && EVIDENCE+="=== package.json (deps) ===\n$(head -c 2500 package.json)\n\n"
[ -f "pyproject.toml" ] && EVIDENCE+="=== pyproject.toml ===\n$(head -c 2500 pyproject.toml)\n\n"
[ -f "requirements.txt" ] && EVIDENCE+="=== requirements.txt ===\n$(head -c 2000 requirements.txt)\n\n"

if command -v rg >/dev/null 2>&1; then
  # Arquivos com upsert/query
  EVIDENCE+="=== Arquivos com vector ops ===\n"
  VDB_FILES=$(rg -l --type py --type ts --type js \
    "\.upsert\(|\.query\(|\.search\(|similarity_search|as_retriever|create_collection|createCollection|create_index" \
    . 2>/dev/null | head -10)
  for f in $VDB_FILES; do
    EVIDENCE+="\n--- $f ---\n$(head -c 4000 "$f" 2>/dev/null)\n"
  done

  # Tenant isolation patterns
  EVIDENCE+="\n=== Tenant isolation matches (namespace/filter/where) ===\n"
  EVIDENCE+="$(rg -n --type py --type ts 'namespace\s*=|tenant_id|where\s*=|filter\s*=|search_kwargs' . 2>/dev/null | head -40)\n"

  # PII na pipeline de embed
  EVIDENCE+="\n=== PII / sanitize matches perto de embed() ===\n"
  EVIDENCE+="$(rg -n --type py --type ts 'sanitize|scrub|presidio|anonymize|redact' . 2>/dev/null | head -20)\n"

  # pgvector schemas
  EVIDENCE+="\n=== pgvector / SQL schemas ===\n"
  EVIDENCE+="$(rg -n -g '*.sql' -g '*.prisma' 'vector\(|VECTOR\(|RLS|ROW LEVEL SECURITY|CREATE POLICY' . 2>/dev/null | head -20)\n"

  # API key exposure no front
  EVIDENCE+="\n=== Vector DB key/client em frontend (suspeito) ===\n"
  EVIDENCE+="$(rg -n --type tsx --type jsx --type ts --type js 'PINECONE_API_KEY|QDRANT_API_KEY|WEAVIATE_API_KEY|new Pinecone\(|PineconeClient\(|chromadb\.' \
    -g '!**/server/**' -g '!**/api/**' -g '!**/backend/**' . 2>/dev/null | head -15)\n"

  # Audit log
  EVIDENCE+="\n=== Audit log matches ===\n"
  EVIDENCE+="$(rg -n --type py --type ts 'audit_log|auditLog|audit\.log|log\.info.*query|log\.info.*upsert' . 2>/dev/null | head -15)\n"
fi

[ -f "${BLINDAR_DIR:-.blindar}/scan.json" ] && EVIDENCE+="\n=== Stack scan ===\n$(head -c 3000 ${BLINDAR_DIR:-.blindar}/scan.json)\n"

if [ -z "$EVIDENCE" ]; then
  log_warn "Sem evidência coletável"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

SYSTEM="Você é o agente vector-db-security do blindar (priority P0).
Avalie segurança do vector database do projeto.

Critérios CRÍTICOS (multi-tenancy vaza dado entre clientes):
1. Tenant isolation: toda query/upsert tem namespace OU filter por tenant_id?
2. PII scrubbing: dados sensíveis (CPF, email, telefone, RG) são scrubbed ANTES de embed?
3. Encryption at rest: Pinecone/Qdrant cloud OK por default; ChromaDB/Milvus self-hosted precisam disco criptografado
4. Frontend exposure: API key ou client de vector DB no bundle do frontend = CRIT
5. Metadata filter injection: user controla filter dict permite bypass de tenant?
6. Audit log: queries/upserts logados?
7. Endpoint sem rate limit (DoS via custo de embedding)
8. pgvector com RLS aplicado?

Severities:
- crit: query/upsert sem isolamento de tenant, API key no frontend, PII embeddado direto, vector DB exposto sem TLS
- high: sem encryption at rest (self-hosted), filter injection possível, sem audit log
- med: sem rate limit, sem cascade delete (LGPD), embedding mismatch
- low: melhorias defense-in-depth

Reporte findings específicos com arquivo/linha. Se evidência insuficiente, indique sev=low com nota."

blindar_api_check "$BLINDAR_AGENT" "$SYSTEM" "$EVIDENCE"
