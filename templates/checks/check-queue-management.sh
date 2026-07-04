#!/usr/bin/env bash
# Materializa: queue-management — tudo que é assíncrono/pesado tem fila
# (backpressure, DLQ, idempotência, retry). Nada de trabalho pesado inline no request.
BLINDAR_AGENT="check-queue-management"
source "$(dirname "$0")/_lib.sh"
log_section "Check: queue-management (filas p/ trabalho assíncrono)"

if ! command -v rg >/dev/null 2>&1; then emit_result "$BLINDAR_AGENT" "skipped" 0; exit 0; fi
IGNORE=(-g '!node_modules' -g '!dist' -g '!.git' -g '!**/*.test.*')
FAIL=0

QUEUE_LIB="(bullmq|bull|@nestjs/bull|bee-queue|agenda|celery|sidekiq|@aws-sdk/client-sqs|amqplib|rabbitmq|kafkajs|@google-cloud/tasks|pg-boss|graphile-worker|rq\.Queue|arq)"
HAS_QUEUE=$(rg -c "$QUEUE_LIB" --type ts --type js --type py "${IGNORE[@]}" 2>/dev/null | wc -l)

# 1. Trabalho pesado/externo inline (email/pdf/relatório/imagem/webhook) sem fila (HIGH)
HEAVY_WORK=$(rg -c "(nodemailer|sendMail|sgMail|@sendgrid|resend\.emails|ses\.send|pdfkit|puppeteer|sharp\(|ffmpeg|generateReport|processImage|sendWebhook)" --type ts --type js --type py "${IGNORE[@]}" 2>/dev/null | wc -l)
if [ "$HEAVY_WORK" -gt 0 ] && [ "$HAS_QUEUE" -eq 0 ]; then
  add_finding "high" "Trabalho pesado/externo (email/pdf/imagem/webhook) sem fila — enfileire (BullMQ/SQS/Celery) pra não travar o request e ter retry/backpressure" "" ""
  FAIL=1
fi

# 2. Tem fila mas sem retry/backoff (MED)
if [ "$HAS_QUEUE" -gt 0 ]; then
  HAS_RETRY=$(rg -c "(attempts|backoff|max_retries|maxRetries|retries|retry_policy)" --type ts --type js --type py "${IGNORE[@]}" 2>/dev/null | wc -l)
  [ "$HAS_RETRY" -eq 0 ] && add_finding "med" "Fila sem política de retry/backoff — jobs falhos somem. Configure attempts + backoff exponencial" "" ""
  # 3. Sem dead-letter queue (MED)
  HAS_DLQ=$(rg -c "(deadLetter|dead-letter|DLQ|failed.*queue|onFailed|removeOnFail)" --type ts --type js --type py "${IGNORE[@]}" 2>/dev/null | wc -l)
  [ "$HAS_DLQ" -eq 0 ] && add_finding "med" "Fila sem dead-letter/tratamento de falha permanente — jobs que falham sempre viram lixo silencioso" "" ""
  # 4. Idempotência (MED)
  HAS_IDEMPOTENT=$(rg -c "(idempoten|jobId|dedup|deduplication|uniqueKey)" --type ts --type js --type py "${IGNORE[@]}" 2>/dev/null | wc -l)
  [ "$HAS_IDEMPOTENT" -eq 0 ] && add_finding "low" "Jobs sem chave de idempotência — retry pode duplicar efeito (email 2x, cobrança 2x)" "" ""
fi

if [ "$FAIL" -eq 1 ]; then emit_result "$BLINDAR_AGENT" "failed" 1; exit 1; fi
# med/low não falham, mas registram
[ "${#FINDINGS[@]}" -gt 0 ] && { emit_result "$BLINDAR_AGENT" "failed" 1; exit 0; }
emit_result "$BLINDAR_AGENT" "passed" 0
