#!/usr/bin/env bash
# Materializa: fallback-resilience — se caiu, como volta? Circuit breaker, retry,
# timeout em toda chamada externa, degradação graciosa.
BLINDAR_AGENT="check-fallback-resilience"
source "$(dirname "$0")/_lib.sh"
log_section "Check: fallback-resilience (timeout/retry/circuit/degradação)"

if ! command -v rg >/dev/null 2>&1; then emit_result "$BLINDAR_AGENT" "skipped" 0; exit 0; fi
IGNORE=(-g '!node_modules' -g '!dist' -g '!.git' -g '!**/*.test.*')
FAIL=0

# Há chamadas externas (rede/IO) no código?
EXTERNAL_CALL=$(rg -c "(fetch\(|axios|http\.request|https\.request|got\(|node-fetch|undici|requests\.(get|post|put)|httpx|urllib)" --type ts --type js --type py "${IGNORE[@]}" 2>/dev/null | wc -l)

if [ "$EXTERNAL_CALL" -gt 0 ]; then
  # 1. Chamada externa sem timeout (HIGH) — trava o sistema quando o upstream pendura
  HAS_TIMEOUT=$(rg -c "(timeout|AbortController|AbortSignal|signal:|AbortSignal\.timeout|Timeout=|connect_timeout|read_timeout)" --type ts --type js --type py "${IGNORE[@]}" 2>/dev/null | wc -l)
  if [ "$HAS_TIMEOUT" -eq 0 ]; then
    add_finding "high" "Chamada externa sem timeout — quando o upstream pendura, seu sistema pendura junto. Defina timeout em toda I/O de rede" "" ""
    FAIL=1
  fi
  # 2. Sem circuit breaker (MED) — evita martelar serviço caído
  HAS_CIRCUIT=$(rg -c "(opossum|cockatiel|brakes|circuit.?breaker|resilience4j|hystrix|pybreaker|CircuitBreaker)" --type ts --type js --type py "${IGNORE[@]}" 2>/dev/null | wc -l)
  [ "$HAS_CIRCUIT" -eq 0 ] && add_finding "med" "Sem circuit breaker — chamadas repetidas a serviço caído amplificam a falha. Use opossum/cockatiel/resilience4j" "" ""
  # 3. Sem retry com backoff (MED)
  HAS_RETRY=$(rg -c "(p-retry|async-retry|retry\(|backoff|tenacity|@Retryable|exponential)" --type ts --type js --type py "${IGNORE[@]}" 2>/dev/null | wc -l)
  [ "$HAS_RETRY" -eq 0 ] && add_finding "med" "Sem retry com backoff — falha transitória vira erro pro usuário. Adicione retry idempotente com jitter" "" ""
fi

# 4. Health/readiness pra orquestrador reiniciar quando cair (MED)
HAS_HEALTH=$(rg -c "(/health|/healthz|/readyz|/ready|healthcheck|readiness|liveness)" --type ts --type js --type py --type yml "${IGNORE[@]}" 2>/dev/null | wc -l)
if [ "$HAS_HEALTH" -eq 0 ] && rg -q "(express|fastify|nestjs|flask|fastapi|gin|actix)" --type ts --type js --type py "${IGNORE[@]}" 2>/dev/null; then
  add_finding "med" "Sem endpoint de health/readiness — orquestrador não sabe quando reiniciar após queda (fallback automático)" "" ""
fi

if [ "$FAIL" -eq 1 ]; then emit_result "$BLINDAR_AGENT" "failed" 1; exit 1; fi
[ "${#FINDINGS[@]}" -gt 0 ] && { emit_result "$BLINDAR_AGENT" "failed" 1; exit 0; }
emit_result "$BLINDAR_AGENT" "passed" 0
