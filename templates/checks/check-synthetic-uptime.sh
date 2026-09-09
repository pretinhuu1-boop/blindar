#!/usr/bin/env bash
# Materializa: synthetic-uptime — quem avisa quando o host inteiro cai?
#
# `/healthz` responde de dentro. Se o processo morreu, o disco encheu, o DNS
# expirou, o certificado venceu ou a máquina desligou, não há ninguém dentro para
# responder — e o silêncio é indistinguível de "está tudo bem". Probe de
# liveness do Kubernetes tem o mesmo defeito quando o cluster é o que caiu.
#
# A única medição honesta de disponibilidade vem de FORA: um serviço em outra
# rede batendo na URL pública em intervalo fixo, com alerta para um humano.
BLINDAR_AGENT="check-synthetic-uptime"
source "$(dirname "$0")/_lib.sh"
log_section "Check: monitor sintético externo (ping de fora)"

# Só se aplica a coisa que fica no ar.
if ! scan_hit 'express|fastify|@nestjs|next|koa|hapi|flask|django|fastapi|gin-gonic|rails|http\.createServer|app\.listen|uvicorn|gunicorn'; then
  log_info "sem serviço exposto — não há o que monitorar de fora"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

# ─── Provedores de monitoramento sintético ───
# roster revisar semestralmente — últ. revisão: 2026-09
# Nome fora desta lista não é "sem monitor": é não classificado. Por isso o
# achado é med e diz o que aceita como prova.
PROVEDORES='uptimerobot|uptime-robot|betteruptime|better-?stack|pingdom|statuscake|healthchecks\.io|hc-ping\.com|cronitor|checkly|updown\.io|freshping|site24x7|pulsetic|oh-?dear|ohdear|datadog.*synthetic|synthetics|grafana.*synthetic|blackbox_?exporter|uptime-?kuma'

ACHOU=$(grep -rIlEi "$PROVEDORES" \
  --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=.blindar \
  --exclude-dir=dist --exclude-dir=build --exclude-dir=.next \
  . 2>/dev/null | head -3)

# CI agendado batendo numa URL externa também vale: é ping de fora, com alerta.
if [ -z "$ACHOU" ]; then
  for wf in .github/workflows/*.yml .github/workflows/*.yaml; do
    [ -f "$wf" ] || continue
    grep -qE '^[[:space:]]*schedule:' "$wf" 2>/dev/null || continue
    grep -qE 'curl|wget|http(s)?://' "$wf" 2>/dev/null && { ACHOU="$wf"; break; }
  done
fi

if [ -z "$ACHOU" ]; then
  add_finding "med" \
    "Sem monitor sintético externo configurado (UptimeRobot, BetterStack, Pingdom, StatusCake, Checkly, healthchecks.io, blackbox_exporter, ou job de CI agendado batendo na URL pública). O /healthz responde de dentro: quando a máquina desliga, o certificado vence ou o DNS expira, não sobra ninguém para responder — e o silêncio fica indistinguível de tudo bem." \
    "" ""
else
  log_pass "monitor sintético externo configurado: $(printf '%s' "$ACHOU" | head -1)"
fi

if [ "${#FINDINGS[@]}" -gt 0 ]; then
  emit_result "$BLINDAR_AGENT" "failed" 0
  exit 0
fi
emit_result "$BLINDAR_AGENT" "passed" 0
exit 0
