#!/usr/bin/env bash
# Wrapper API: rag-quality — qualidade de pipeline RAG via Claude
BLINDAR_AGENT="check-rag-quality"
source "$(dirname "$0")/_lib.sh"
source "$(dirname "$0")/_api_wrapper.sh"

log_section "Check: rag-quality (qualidade RAG via Claude API)"

# Detecta uso de RAG no projeto
RAG_HIT=0
if command -v rg >/dev/null 2>&1; then
  if rg -l --type py --type ts --type js \
       "chromadb|pinecone|weaviate|qdrant|milvus|pgvector|llama_index|llamaindex|langchain.*VectorStore|@pinecone-database|@qdrant/js-client|weaviate-ts-client" \
       . >/dev/null 2>&1; then
    RAG_HIT=1
  fi
fi

if [ "$RAG_HIT" -eq 0 ]; then
  log_info "Nenhum vector DB / RAG lib detectado — skipped"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

# Coleta evidência (limite ~50k chars total)
EVIDENCE=""
EVIDENCE+="=== RAG detection ===\nProjeto usa vector DB / RAG lib.\n\n"

# Manifests
[ -f "package.json" ] && EVIDENCE+="=== package.json (deps) ===\n$(head -c 2500 package.json)\n\n"
[ -f "pyproject.toml" ] && EVIDENCE+="=== pyproject.toml ===\n$(head -c 2500 pyproject.toml)\n\n"
[ -f "requirements.txt" ] && EVIDENCE+="=== requirements.txt ===\n$(head -c 2000 requirements.txt)\n\n"

# Arquivos com chamadas relevantes (top 8)
if command -v rg >/dev/null 2>&1; then
  EVIDENCE+="=== Arquivos com embeddings / vector ops ===\n"
  RAG_FILES=$(rg -l --type py --type ts --type js \
    "\.embed\(|\.embeddings\.|embedding_function|OpenAIEmbeddings|HuggingFaceEmbeddings|VoyageEmbeddings|\.upsert\(|\.query\(|similarity_search|as_retriever|vector_store|VectorStore" \
    . 2>/dev/null | head -8)
  for f in $RAG_FILES; do
    EVIDENCE+="\n--- $f ---\n$(head -c 3500 "$f" 2>/dev/null)\n"
  done

  # Chunking config snippets
  EVIDENCE+="\n=== Chunking config matches ===\n"
  EVIDENCE+="$(rg -n --type py --type ts 'chunk_size|chunkSize|chunk_overlap|chunkOverlap|RecursiveCharacterTextSplitter|SentenceSplitter|MarkdownHeaderTextSplitter|SemanticChunker' . 2>/dev/null | head -30)\n"

  # Retrieval config
  EVIDENCE+="\n=== Retrieval / reranker matches ===\n"
  EVIDENCE+="$(rg -n --type py --type ts 'search_kwargs|top_k|topK|n_results|rerank|Rerank|hybrid_search|BM25' . 2>/dev/null | head -30)\n"

  # Eval framework
  EVIDENCE+="\n=== Eval framework matches ===\n"
  EVIDENCE+="$(rg -n --type py --type ts 'ragas|RAGAS|trulens|TruLens|llama_index.*evaluation|context_precision|faithfulness' . 2>/dev/null | head -15)\n"
fi

# Scan da skill blindar
[ -f "${BLINDAR_DIR:-.blindar}/scan.json" ] && EVIDENCE+="\n=== Stack scan ===\n$(head -c 3000 ${BLINDAR_DIR:-.blindar}/scan.json)\n"

if [ -z "$EVIDENCE" ]; then
  log_warn "Sem evidência coletável"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

SYSTEM="Você é o agente rag-quality do blindar.
Avalie a qualidade do pipeline RAG (Retrieval-Augmented Generation) do projeto.

Critérios:
1. Chunking strategy: tamanho, overlap, splitter usado (Recursive / Semantic / Sentence-window / Markdown-aware / Parent-child)
2. Embedding model fit: modelo escolhido vs domínio (PT-BR? jurídico/médico? código?). text-embedding-ada-002 = legacy.
3. Retrieval: top-k razoável (5-20), reranker presente (Cohere/Voyage/BGE), hybrid search (BM25+dense)
4. Citation grounding: resposta inclui sources/chunk_ids?
5. Eval framework: RAGAS, TruLens ou similar em CI?
6. Cache de embeddings (não recomputa idêntico)
7. Reindex incremental (não rebuild full)
8. Mesmo embedding model entre index e query

Severities:
- crit: chunk size absurdo (>4k), modelo embedding errado pro domínio
- high: zero reranker em produção, sem citation, sem eval framework
- med: chunk size sub-ótimo, falta cache, k muito baixo (k=1-2)
- low: melhorias incrementais (hybrid search, parent-child)

Reporte findings específicos com arquivo/linha quando possível.
Se sinais insuficientes, indique informação faltante com severity=low."

blindar_api_check "$BLINDAR_AGENT" "$SYSTEM" "$EVIDENCE"
