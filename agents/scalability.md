# agent: scalability

Sistema continua respondendo sob **crescimento de carga** (10x usuários,
10x dados, 10x fan-out). Complementa [`resilience.md`](resilience.md):
resilience = sobreviver a falha. Scalability = sobreviver a sucesso.

## Quando ativar

Discovery sinalizou pelo menos um dos sinais:
- Estado em memória do processo (sessão, cache local) — bloqueia
  scale horizontal
- Endpoint que faz fan-out (1 request → N requests downstream)
- DB sem connection pool dimensionado
- Cache sem TTL ou sem proteção de stampede
- Job síncrono em request path que pode demorar > 1s

Ou quando o operador declara crescimento esperado
(`.scaling-target=10x`).

## Frentes de ataque

### 1. Statelessness (12-factor app)

Pré-requisito pra horizontal scaling. Sem isso, replicar processo é
inútil.

- **Sessão em store externo** (Redis, DB, JWT assinado), nunca em
  memória do processo
- **Cache local apenas como "leitura barata otimista"** — fonte da
  verdade fica externa
- **Upload em storage externo** (S3, GCS, R2), não disco local
- **Logs em stdout**, coletados por agente externo
- **Config via env**, build artifact idêntico em todos ambientes

### 2. Idempotência

Pré-requisito pra retry seguro. Sem isso, retry duplica cobrança/efeito.

- **Idempotency key** em todo endpoint que muda estado (POST/PUT/DELETE).
  Cliente envia `Idempotency-Key: <uuid>`; servidor cacheia resposta
  por janela (24h típico).
- **Deduplicação no consumer de fila** — mesmo evento processado 2x
  precisa produzir o mesmo resultado.
- **Operações comutativas onde possível** (set vs increment).

### 3. Caching com proteção

Cache mal feito é pior que sem cache.

- **TTL sempre.** Cache sem expiração é vazamento programado.
- **Cache stampede** — quando key expira, N requests batem no DB ao
  mesmo tempo. Mitigação:
  - SWR (stale-while-revalidate): serve stale + recalcula em bg
  - Lock distribuído (Redis SETNX): 1 thread recalcula, resto espera
  - Probabilistic early expiration
- **Negative cache** com TTL curto (10-60s) pra evitar repetir
  query pesada com resultado vazio
- **Cache warming** opcional pra keys quentes pós-deploy
- **Camadas**: CDN → app cache → DB cache. Cada uma com TTL próprio.

### 4. Queue + backpressure

Trabalho pesado fora do request path. Mas com limites.

- **Dead Letter Queue (DLQ)** — mensagem que falha N vezes não fica
  reprocessando pra sempre
- **Visibility timeout** apropriado pro tempo real de processamento
- **Concurrency limit por worker** (não puxa 1000 mensagens se só
  processa 10/s)
- **Backpressure no producer** — se queue está cheia, producer
  reduz taxa ou rejeita com 503 (não engole silenciosamente)
- **Ordering**: declarar se é necessário (FIFO) ou não. FIFO custa
  throughput.

### 5. Database

Gargalo mais comum em scale.

- **Connection pool dimensionado** — não 1 conexão por request.
  Pool tamanho ≈ `(núcleos × 2) + storage_spindles` (Postgres);
  ajuste com benchmark real.
- **PgBouncer / RDS Proxy** entre app e DB quando connections >
  pool limit
- **Read replicas** pra queries que aceitam ~1s de lag
  (analytics, listings; nunca para "ler após escrever")
- **Index review** — query lenta sob carga geralmente é falta de
  index ou index ignorado por estatística desatualizada
- **N+1 query** auditado em CI (orm linter)
- **Migrations zero-downtime** — não ALTER TABLE em tabela quente.
  Padrão: criar coluna nova → backfill → swap → drop old.

### 6. Hot keys / fan-out

Crescimento desbalanceado.

- **Hot key detection** — um usuário/recurso recebe 1000x mais tráfego
  que mediano. Mitigação: cache mais agressivo nessa key específica,
  ou sharding por sub-chave.
- **Fan-out amplification** — endpoint A chama 5 downstreams; cada
  downstream chama 3 mais; 1 request vira 15. Medir e quebrar com
  cache ou batch.
- **Thundering herd** após deploy/restart — milhares de instâncias
  reconectando ao DB. Mitigação: jitter no reconnect, exponential
  backoff.

### 7. Horizontal scaling readiness

- **Health endpoints separados**: `/live` (processo respira) vs
  `/ready` (pronto pra receber tráfego). Orquestrador roteia
  só os ready.
- **Graceful shutdown**: SIGTERM → drena requests em vôo →
  desregistra do load balancer → sai (até `terminationGracePeriodSeconds`)
- **Boot time razoável** — < 30s ideal. Boot lento dificulta
  autoscaling (escalou tarde demais).
- **Sticky sessions: NÃO.** Se você precisa de sticky, sessão não
  está externalizada. Volta pro item 1.

## Prompt

```
Audit scalability posture. Para cada item abaixo, marque GAP ou OK
com evidência:

1. Statelessness (sessão externalizada, sem disk-state, logs stdout)
2. Idempotency-Key implementada em POST/PUT/DELETE críticos
3. Cache: TTL sempre, proteção de stampede (SWR ou lock), camadas
4. Queue: DLQ, backpressure, concurrency limit
5. DB: pool dimensionado, replicas onde cabe, N+1 auditado, migrations
   zero-downtime
6. Hot keys / fan-out: detectados e medidos
7. Horizontal scaling: /live + /ready separados, graceful shutdown,
   sem sticky session

Implement top-1 gap (≤80 LOC + config):
- Não inventar — atacar o gap real com evidência (load test, RUM,
  log de produção).
- Antes/depois mensurado (k6, vegeta, hey) na descrição do PR.
- Teste de regressão: cenário de carga que provou o problema vira
  teste automatizado.
- sec.html: categoria scalability, ATKs por gap detectado.

Princípio: SCALE NÃO É PERFORMANCE. Otimizar de 50ms pra 30ms não
ajuda se cair em 100 usuários simultâneos. Scale = sustentar carga,
não responder rápido.
```

## Princípios não-negociáveis

- **Statelessness é pré-requisito**, não tradeoff. Sem isso, nada
  mais escala.
- **Idempotência é pré-requisito de retry.** Retry sem idempotência
  causa bugs piores que o original.
- **Sticky session = bug.** Trate como sintoma de sessão mal feita.
- **Medir em carga, não em isolamento.** Sistema responde em 50ms
  com 1 user — irrelevante. Resposta em 95p com 1000 simultâneos
  é o que importa.
- **Auto-scaling não resolve gargalo de DB.** Adicionar 10 instâncias
  app só transfere o problema. DB e cache precisam escalar junto.
- **Load test antes de ir pra produção real.** k6/vegeta/Locust contra
  staging com carga 3x esperada.

## Teste obrigatório

- **Happy**: load test 1x carga esperada → p95 dentro do SLO
- **Edge**: load test 3x carga esperada → degrada graciosamente
  (503 com Retry-After, não 500 com stack trace)
- **Attack**: cenário que originou o gap (cache stampede simulado,
  fan-out medido, etc.)

## Diferença vs resilience

| Aspecto | resilience.md | scalability.md |
|---|---|---|
| Pergunta | "Sistema sobrevive a falha de X?" | "Sistema sobrevive a 10x carga?" |
| Ferramenta principal | Circuit breaker | Cache + queue + statelessness |
| Sintoma típico | Cascade failure | DB ou main thread saturada |
| Teste | Chaos engineering | Load testing |

Sobreposição: ambos usam pools, backpressure, breakers. Roteamento:
"caiu agora" → resilience. "vai cair em 10x" → scalability.

## Adaptação por stack

| Stack | Atenção extra |
|---|---|
| **Node** | Single-thread main loop; worker_threads pra CPU-bound |
| **Python (sync)** | GIL + 1 process por núcleo; gunicorn workers; async pra I/O |
| **Python (async)** | asyncio loop não bloqueia em CPU; sync work → run_in_executor |
| **Go** | Goroutines baratas, mas channel/mutex podem deadlockar — perfilar |
| **JVM (Java/Kotlin)** | GC tuning vira problema acima de 8GB heap; considerar ZGC |
| **Postgres** | Connection pool é crítico; PgBouncer praticamente obrigatório |
| **MongoDB** | Sharding key escolha define se escala ou não — irreversível |

## Benchmark obrigatório (v0.6.0)

Cada mudança de scalability **mede antes e depois**.

### DB benchmark

```sql
-- Antes
EXPLAIN (ANALYZE, BUFFERS) <query>;
-- ... aplica index/refactor ...
-- Depois
EXPLAIN (ANALYZE, BUFFERS) <query>;
```

PR description carrega ambos. Se "depois" não for ≥ 30% melhor, fix
não justifica.

### Cache benchmark

```bash
# Antes (sem cache): mede p95 com k6
k6 run --vus 100 --duration 2m loadtest.js
# Aplica cache
# Depois
k6 run --vus 100 --duration 2m loadtest.js
```

Reduction esperada: p95 cache hit ≥ 80% mais rápida que miss.

### Connection pool

```python
# Mede pool exhaustion sob carga
import asyncio
async def hammer():
    tasks = [client.get('/api/heavy') for _ in range(500)]
    return await asyncio.gather(*tasks, return_exceptions=True)

# Conta quantas tasks ficaram "waiting for pool" > 1s
```

### Stampede

Simula expiração simultânea:

```python
# Invalida key, dispara 50 requests imediatos
await cache.delete(key)
results = await asyncio.gather(*[get_resource(key) for _ in range(50)])
# Verifica: 1 hit no DB, 49 esperaram e receberam mesma resposta
```

Spec completa em
[`docs/specs/load-test-harness.md`](../docs/specs/load-test-harness.md).

## Mapeamento de frameworks

| Framework | Item relacionado |
|---|---|
| AWS Well-Architected | Pilar Performance Efficiency |
| 12-Factor App | Factor VI (processes), VIII (concurrency), IX (disposability) |
| OWASP ASVS | V14 (configuration), não cobre scalability diretamente |
| NIST SP 800-160 | Resilience engineering (parcial) |

## Limitações honestas

- **Não cobre sharding multi-region.** Disponibilidade global é
  outra liga.
- **Não cobre cost optimization.** Você pode escalar burro (jogar
  máquina) e funciona; custa caro.
- **Não substitui capacity planning.** Skill ajuda com técnica;
  estimativa de carga vem do negócio.
