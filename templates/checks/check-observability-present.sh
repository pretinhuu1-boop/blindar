#!/usr/bin/env bash
# Materializa: observability-present — existe métrica exposta e existe alguém
# sendo acordado?
#
# O `/healthz` responde a uma pergunta ("estou de pé?") e nenhuma outra. Ele não
# diz que a latência triplicou, que a fila cresce há quarenta minutos, que a taxa
# de erro passou de 0,3% para 12%. Nada disso derruba o processo — e por isso
# nada disso aparece no health check.
#
# Duas perguntas, nesta ordem:
#   1. Existe MÉTRICA exposta (endpoint Prometheus, OTel, coletor)?
#   2. Existe ALERTA — alguém é acordado, ou o painel só existe para ser olhado
#      por quem já desconfia que tem algo errado?
#
# Painel sem alerta é arqueologia: serve para entender o incidente depois, não
# para descobri-lo. O agente `observability` cobre logger e health; aqui a
# pergunta é a que fica de fora: quem é paginado quando cai?
BLINDAR_AGENT="check-observability-present"
source "$(dirname "$0")/_lib.sh"
log_section "Check: métrica exposta + alerta configurado"

if ! scan_hit 'express|fastify|@nestjs|next|koa|hapi|flask|django|fastapi|gin-gonic|rails|http\.createServer|app\.listen|uvicorn|gunicorn|worker|consumer'; then
  log_info "sem serviço de longa duração — não se aplica"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

# ─── 1. Métrica ───
METRICAS=$(scan_src 'prom-client|prometheus_client|express-prom-bundle|@opentelemetry|opentelemetry-|micrometer|django-prometheus|/metrics|prometheus\.(Counter|Histogram|Gauge)|makeCounterProvider|StatsD|dogstatsd' | head -3)
# Config de coleta versionada também conta.
if [ -z "$METRICAS" ]; then
  for f in prometheus.yml prometheus.yaml otel-collector.yaml otel-collector-config.yaml \
           monitoring/prometheus.yml observability/otel.yaml; do
    [ -f "$f" ] && { METRICAS="$f:1:coletor"; break; }
  done
fi

# ─── 2. Alerta ───
ALERTA=$(scan_src 'alertmanager|pagerduty|opsgenie|@sentry/|sentry_sdk|sentry-sdk|Sentry\.init|bugsnag|rollbar|slack_webhook|SLACK_WEBHOOK|alerting:|notification_?polic|for:[[:space:]]*[0-9]+[ms]' | head -3)
if [ -z "$ALERTA" ]; then
  for f in alertmanager.yml alertmanager.yaml monitoring/alertmanager.yml \
           sentry.properties sentry.client.config.ts sentry.server.config.ts; do
    [ -f "$f" ] && { ALERTA="$f:1:config"; break; }
  done
fi
if [ -z "$ALERTA" ]; then
  RULES=$(ls -1 *.rules.yml *.rules.yaml alerts/*.yml alerts/*.yaml \
          monitoring/*.rules.yml observability/*.rules.yml 2>/dev/null | head -1)
  [ -n "$RULES" ] && ALERTA="$RULES:1:regras"
fi

# ─── 3. Log estruturado (não substitui alerta, mas muda a severidade) ───
LOGGER=$(scan_src '"(pino|winston|bunyan|structlog|loguru|zerolog|zap)"|require\(.(pino|winston|bunyan).\)|from .(pino|winston|structlog)' | head -1)

if [ -z "$METRICAS" ] && [ -z "$ALERTA" ]; then
  add_finding "high" \
    "Sem endpoint de métricas (/metrics, Prometheus, OTel) E sem configuração de alerta (Alertmanager, regras Grafana, PagerDuty, Opsgenie, Sentry). O /healthz existe, mas quem é paginado quando cai? Hoje a resposta é: o cliente, por WhatsApp." \
    "" ""
elif [ -z "$ALERTA" ]; then
  ONDE=$(printf '%s\n' "$METRICAS" | head -1 | cut -d: -f1)
  if [ -n "$LOGGER" ]; then
    add_finding "med" \
      "Há métrica exposta e log estruturado, mas NENHUM alerta configurado — o painel só é olhado por quem já desconfia que tem algo errado. Ninguém é acordado às 3h. Defina ao menos: taxa de erro, latência p95 e profundidade de fila, cada um com destinatário." \
      "$ONDE" ""
  else
    add_finding "med" \
      "Métrica exposta sem nenhum alerta configurado — coletar não é observar. Aponte um Alertmanager, regra de Grafana, Sentry ou PagerDuty para pelo menos taxa de erro e latência." \
      "$ONDE" ""
  fi
elif [ -z "$METRICAS" ]; then
  ONDE=$(printf '%s\n' "$ALERTA" | head -1 | cut -d: -f1)
  add_finding "med" \
    "Há canal de alerta configurado, mas nenhuma métrica exposta (/metrics, OTel, prom-client) — o alerta só dispara com o que já quebrou; degradação (latência subindo, fila crescendo) passa despercebida até virar queda." \
    "$ONDE" ""
else
  log_pass "métrica exposta ($(printf '%s\n' "$METRICAS" | head -1 | cut -d: -f1)) e alerta configurado ($(printf '%s\n' "$ALERTA" | head -1 | cut -d: -f1))"
fi

if [ "${#FINDINGS[@]}" -gt 0 ]; then
  case "${FINDINGS[*]}" in
    *'"severity":"high"'*|*'"severity":"crit"'*) emit_result "$BLINDAR_AGENT" "failed" 1; exit 1 ;;
  esac
  emit_result "$BLINDAR_AGENT" "failed" 0
  exit 0
fi
emit_result "$BLINDAR_AGENT" "passed" 0
exit 0
