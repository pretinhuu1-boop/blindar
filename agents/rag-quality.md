---
name: rag-quality
category: core
module: 2
priority: P1
description: |
  Avalia qualidade de pipelines RAG (Retrieval-Augmented Generation):
  chunking strategy, embedding model fit, retrieval precision/recall,
  reranking, citation grounding e hallucination rate. Detecta uso de
  vector DBs (chromadb, pinecone, weaviate, pgvector, qdrant, milvus)
  e avalia se a configuração segue best practices 2026. Skipped se
  projeto não usa RAG.
---

# Agent: rag-quality

## Missão

RAG mal configurado é a causa #1 de "IA que mente com confiança". Chunk
grande demais perde precisão; pequeno demais perde contexto. Embedding
genérico (text-embedding-3-small) num domínio jurídico/médico recupera
lixo. Sem reranker, top-k=10 traz 7 irrelevantes. Sem grounding/citation,
modelo alucina por cima do contexto. Este agente **mede e ajusta**.

## Quando rodar

- Módulo 2 selecionado (sempre que projeto tem IA/RAG)
- Detecção automática: lib de vector DB presente
- Operador pediu "RAG", "embeddings", "retrieval", "alucinação"

## A. Detecção de RAG no projeto

```bash
# Python
rg -l "chromadb|pinecone|weaviate|qdrant|milvus|pgvector|llama_index|langchain.*VectorStore" \
  --type py

# Node/TS
rg -l "@pinecone-database|chromadb|weaviate-ts-client|@qdrant/js-client|llamaindex|langchain" \
  --type ts --type js

# Embeddings
rg -n "\.embed\(|\.embeddings\.|embedding_function|OpenAIEmbeddings|HuggingFaceEmbeddings|VoyageEmbeddings"

# Vector ops
rg -n "\.upsert\(|\.query\(|similarity_search|as_retriever|vector_store"
```

Sem hit em nenhum: **skipped**.

## B. Chunking strategy (avaliar)

| Estratégia | Quando | Trade-off |
|---|---|---|
| Fixed size (512/1024 tokens) | Default rápido | Quebra meio de frase/ideia |
| Recursive char splitter | Texto genérico | Melhor que fixed, ainda burro |
| Semantic splitter | Conteúdo denso | Mais lento, melhor coerência |
| Sentence-window | QA factual | Janela ±N frases pra contexto |
| Parent-child | Docs hierárquicos | Chunk pequeno indexa, parent retorna |
| Markdown/code-aware | Docs estruturados | Respeita headers/funções |

**Greps:**
```bash
# Chunk size hardcoded
rg -n "chunk_size|chunkSize" --type py --type ts
rg -n "chunk_overlap|chunkOverlap" --type py --type ts

# Splitter
rg -n "RecursiveCharacterTextSplitter|SentenceSplitter|MarkdownHeaderTextSplitter|SemanticChunker"
```

**Heurística 2026:**
- Texto narrativo: 512 tokens + overlap 50 (~10%)
- Código: AST-aware splitter (tree-sitter)
- Markdown: header-aware preserva seções
- PDFs/papers: parent-child com chunk 256 / parent 2048

## C. Embedding model fit

| Modelo | Domínio | Custo | Quando |
|---|---|---|---|
| `text-embedding-3-small` (OpenAI) | Geral EN | $ | Default barato |
| `text-embedding-3-large` | Geral multi-lang | $$ | Default qualidade |
| `voyage-3` / `voyage-3-large` | Geral, RAG-tuned | $$ | Top-tier 2026 |
| `voyage-code-3` | Código | $$ | Code search |
| `voyage-law-2` | Jurídico | $$ | Domínio legal |
| `BAAI/bge-m3` (HF) | Multi-lang on-prem | grátis | Self-hosted |
| `text-multilingual-embedding-002` (Vertex) | Multi-lang PT-BR | $ | GCP stack |

**Anti-pattern:** `text-embedding-ada-002` ainda em uso (legacy 2022).

**Domínio específico (PT-BR jurídico/médico/financeiro):**
modelo genérico inglês = recall ruim. Avaliar fine-tune de embedding
ou usar modelo multilíngue (voyage-3, bge-m3).

## D. Retrieval — top-k + reranking

```python
# ❌ Top-k=3 sem reranker — perde contexto relevante
retriever = vectorstore.as_retriever(search_kwargs={"k": 3})

# ✅ Top-k=20 + reranker → top 5 final
retriever = vectorstore.as_retriever(search_kwargs={"k": 20})
reranker = CohereRerank(top_n=5)  # ou voyage-rerank-2, BGE-reranker
```

**Heurística:** retrieve 20, rerank pra 3-5, passa pro LLM.

**Greps:**
```bash
rg -n "search_kwargs|top_k|topK|n_results"
rg -n "rerank|Rerank|CohereRerank|VoyageReranker|BGEReranker"
rg -n "hybrid_search|BM25|sparse_dense"  # hybrid = dense + sparse
```

## E. Citation grounding & hallucination

**Sem citation = você não sabe se o modelo respondeu do contexto ou da
training data.** Toda resposta RAG deve incluir `sources: [chunk_id, ...]`.

```python
# ✅ Pattern
response = {
    "answer": "...",
    "sources": [{"id": chunk.id, "score": chunk.score, "preview": chunk.text[:100]}]
}
```

**Grounding check:** após gerar, validar que cada claim do answer tem
suporte em algum chunk recuperado. Libs: RAGAS (faithfulness),
TruLens (groundedness), Ragas Context Precision.

## F. Evaluation framework

**Métricas obrigatórias:**

| Métrica | Lib | Threshold prod |
|---|---|---|
| Context Precision | RAGAS | > 0.7 |
| Context Recall | RAGAS | > 0.8 |
| Faithfulness (grounding) | RAGAS / TruLens | > 0.85 |
| Answer Relevancy | RAGAS | > 0.7 |
| Hit Rate @ k | LlamaIndex | > 0.9 |
| MRR (Mean Reciprocal Rank) | LlamaIndex | > 0.7 |

**Pipeline mínima:**
1. Golden dataset (50-200 Q&A pairs anotadas)
2. CI roda RAGAS em PR que toca retrieval
3. Threshold quebrado = falha build

## G. Anti-padrões (CRIT/HIGH)

- ❌ `text-embedding-ada-002` em projeto novo (legacy, troque por v3)
- ❌ Chunk size = 8000 tokens (passa contexto inteiro = sem retrieval)
- ❌ `k=1` (single chunk, sem redundância)
- ❌ Sem overlap entre chunks (perde info na borda)
- ❌ Sem reranker em produção com k > 5
- ❌ Embedding inglês em corpus PT-BR
- ❌ Resposta sem citation/sources
- ❌ Zero evaluation framework (sem RAGAS/TruLens)
- ❌ Reindex manual (não incremental, custa fortuna)
- ❌ Sem cache de embeddings (recomputa idêntico)
- ❌ Misturando embedding models entre query e index (incompatível)
- ❌ Metadata filter ignorado (busca em tudo, devolve cross-tenant)

## H. Output esperado em sec.html

```
┌─ RAG Quality (Módulo 2) ─────────────────────────────────┐
│ Vector DB detectado          : pgvector ✅                │
│ Embedding model              : voyage-3-large ✅          │
│ Chunk strategy               : recursive 512/50 ✅        │
│ Reranker ativo               : Cohere rerank-3 ✅         │
│ Hybrid search (BM25+dense)   : ✅                         │
│ Citation/sources retornados  : ✅ schema validado         │
│ Eval framework               : RAGAS em CI ✅             │
│ Context Precision            : 0.78 ✅                    │
│ Faithfulness                 : 0.91 ✅                    │
│ Embedding cache              : Redis 7d TTL ✅            │
│ Status                       : ✅ PRODUCTION-READY        │
└───────────────────────────────────────────────────────────┘
```

## I. Interação com outros agentes

- **vector-db-security**: garante isolamento tenant em queries
- **fine-tune-data-leak**: PII em training set vale também pra docs indexados
- **observability-ai**: tracing de retrieval (latência, hit rate)
- **prompt-injection**: contexto recuperado pode trazer prompt injection
- **cost-control-ai**: embeddings + reranking custam $$, monitorar
