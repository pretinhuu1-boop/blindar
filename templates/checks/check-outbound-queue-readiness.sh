#!/usr/bin/env bash
# Materializa: outbound-queue-readiness — efeito de saída rodando dentro da
# requisição.
#
# Enviar e-mail, disparar webhook, mandar notificação e postar em API de
# terceiro têm três propriedades que não combinam com o ciclo de uma requisição
# HTTP: são lentos (centenas de ms a segundos), falham por motivo alheio (o
# provedor caiu, não você), e o cliente do outro lado está esperando.
#
# Feito inline, o resultado é o pior dos dois mundos: a latência do seu endpoint
# passa a ser a latência do provedor mais lento, e quando ele falha o usuário vê
# erro numa operação que já deu certo — o pedido foi criado, só o e-mail não
# saiu. Ou pior: você reverte o pedido por causa do e-mail.
#
# Com fila, o efeito de saída ganha o que precisa: retry com backoff, isolamento
# de falha, e uma resposta imediata para quem está esperando.
BLINDAR_AGENT="check-outbound-queue-readiness"
source "$(dirname "$0")/_lib.sh"
log_section "Check: efeito de saída (e-mail/webhook/notificação) fora da requisição"

SAIDA=$(scan_src '(sendMail|send_mail|sendEmail|send_email|\.emails?\.send|nodemailer|sendgrid|mailgun|postmark|resend|smtplib|django\.core\.mail|ActionMailer|sendNotification|push\.send|webhook[^;]*(post|send|fetch|axios)|axios\.post\(.https|fetch\(.https[^)]*webhook|twilio[^;]*messages\.create|whatsapp[^;]*send)' \
  | grep -viE '(test|spec|mock|fixture|example|\.md:)' | head -12)

if [ -z "$SAIDA" ]; then
  log_info "nenhum efeito de saída (e-mail, webhook, notificação) — não se aplica"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

# ─── Existe fila com retry? ───
FILA=$(scan_src '(bullmq|BullMQ|new Queue\(|bee-queue|agenda|kue|celery|rq\.Queue|dramatiq|sidekiq|SQS|sqs-consumer|@aws-sdk/client-sqs|rabbitmq|amqplib|kafkajs|pgboss|pg-boss|graphile-worker|inngest|trigger\.dev|@upstash/qstash|temporal)' | head -3)

ARQ=$(printf '%s\n' "$SAIDA" | head -1 | cut -d: -f1)
LN=$(printf '%s\n' "$SAIDA" | head -1 | cut -d: -f2)

if [ -z "$FILA" ]; then
  add_finding "med" \
    "Efeito de saída (e-mail/webhook/notificação) executado sem nenhuma fila com retry e backoff no projeto. Inline, a latência do seu endpoint vira a latência do provedor mais lento, e a falha dele aparece como erro numa operação que já deu certo — o pedido foi criado, só o e-mail não saiu. Enfileire e responda imediatamente." \
    "$ARQ" "$LN"
else
  log_pass "fila presente ($(printf '%s\n' "$FILA" | head -1 | cut -d: -f1))"
  # Fila existe, mas o handler HTTP dispara o envio direto assim mesmo. É o caso
  # mais comum: a infraestrutura foi montada e um caminho continua inline.
  INLINE=""
  while IFS=: read -r f ln resto; do
    [ -z "${f:-}" ] && continue
    [ -f "$f" ] || continue
    # Arquivo que trata requisição HTTP e envia direto, sem enfileirar.
    grep -qE '(app\.(get|post|put|patch|delete)\(|router\.(get|post|put|patch)\(|@(Get|Post|Put|Patch)\(|@app\.route|@router\.(get|post))' "$f" 2>/dev/null || continue
    grep -qE '(\.add\(|enqueue|publish\(|sendMessage\(|\.perform_async|delay\(|\.emit\(|dispatch\()' "$f" 2>/dev/null && continue
    INLINE="$f:$ln"
    break
  done <<EOT
$SAIDA
EOT
  if [ -n "$INLINE" ]; then
    add_finding "med" \
      "Há fila no projeto, mas este handler HTTP dispara o efeito de saída direto, sem enfileirar — o caminho que ficou de fora é o que vai falhar em produção, e ninguém lembra dele porque 'o projeto usa fila'." \
      "$(printf '%s' "$INLINE" | cut -d: -f1)" "$(printf '%s' "$INLINE" | cut -d: -f2)"
  fi
fi

if [ "${#FINDINGS[@]}" -gt 0 ]; then
  emit_result "$BLINDAR_AGENT" "failed" 0
  exit 0
fi
emit_result "$BLINDAR_AGENT" "passed" 0
exit 0
