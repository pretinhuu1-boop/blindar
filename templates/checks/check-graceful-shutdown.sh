#!/usr/bin/env bash
# Materializa: graceful-shutdown — o deploy corta a transação no meio.
#
# Orquestrador (Docker, Kubernetes, systemd, o provedor de PaaS) manda SIGTERM e
# espera alguns segundos antes do SIGKILL. Um processo que ignora o SIGTERM é
# morto no meio do que estava fazendo: requisição sem resposta, transação sem
# commit nem rollback, mensagem consumida da fila e nunca processada, conexão de
# banco deixada pendurada até o timeout.
#
# Nada disso aparece em teste, porque o teste não reinicia o processo no meio da
# carga. Aparece em produção, a cada deploy, em proporção ao tráfego — e vira
# "erro intermitente que ninguém reproduz".
#
# O contrato mínimo: parar de aceitar conexão nova, terminar o que está em voo,
# fechar pool de banco e consumidor de fila, e só então sair.
BLINDAR_AGENT="check-graceful-shutdown"
source "$(dirname "$0")/_lib.sh"
log_section "Check: encerramento gracioso (SIGTERM drena o que está em voo)"

SERVIDOR=$(scan_src '(app\.listen|http\.createServer|server\.listen|uvicorn\.run|gunicorn|createServer\(|NestFactory\.create|Bun\.serve|Deno\.serve|worker\.run|consumer\.run|new Worker\()' \
  | grep -viE '(test|spec|mock|fixture)' | head -5)
if [ -z "$SERVIDOR" ]; then
  log_info "sem processo de longa duração (servidor ou worker) — não se aplica"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi
ARQ=$(printf '%s\n' "$SERVIDOR" | head -1 | cut -d: -f1)
LN=$(printf '%s\n' "$SERVIDOR" | head -1 | cut -d: -f2)

# ─── 1. O sinal é escutado? ───
SINAL=$(scan_src '(SIGTERM|SIGINT|signal\.signal|beforeExit|onModuleDestroy|enableShutdownHooks|@app\.on_event\(.shutdown|lifespan|atexit\.register|shutdown_?handler|graceful)' \
  | grep -viE '(test|spec|mock|fixture)' | head -5)

if [ -z "$SINAL" ]; then
  add_finding "med" \
    "Nenhum handler de SIGTERM/SIGINT — o processo é morto no meio do que estava fazendo a cada deploy: requisição sem resposta, transação sem commit nem rollback, mensagem consumida da fila e nunca processada. O sintoma vira 'erro intermitente que ninguém reproduz', proporcional ao tráfego." \
    "$ARQ" "$LN"
else
  ARQ_S=$(printf '%s\n' "$SINAL" | head -1 | cut -d: -f1)
  LN_S=$(printf '%s\n' "$SINAL" | head -1 | cut -d: -f2)
  log_pass "handler de sinal encontrado em $ARQ_S:$LN_S"

  # ─── 2. O handler DRENA, ou só sai mais rápido? ───
  # `process.on("SIGTERM", () => process.exit(0))` é pior que não ter handler:
  # transforma um kill em 10s num kill imediato, e parece resolvido.
  if scan_hit 'SIGTERM[^)]*\)[^{]*\{?[^}]{0,80}process\.exit' ; then
    add_finding "med" \
      "Handler de SIGTERM que chama process.exit direto — isso não drena nada; encurta a janela que o orquestrador dava e mata o que estava em voo mais cedo. Feche o servidor (server.close), espere as requisições em curso, feche pool e consumidores, e só então saia." \
      "$ARQ_S" "$LN_S"
  elif ! scan_hit '(server\.close|\.close\(\)|closeAllConnections|shutdown\(|\.disconnect\(|\.\$disconnect|pool\.end|await[^;]*close|drain\(|stop\()'; then
    add_finding "med" \
      "Handler de sinal presente, mas sem fechamento explícito de servidor, pool de banco ou consumidor de fila (server.close, pool.end, disconnect, drain). Escutar o sinal sem drenar não muda o resultado: o que estava em voo morre igual." \
      "$ARQ_S" "$LN_S"
  else
    log_pass "encerramento drena conexões antes de sair"
  fi
fi

# ─── 3. O sinal chega até o processo? ───
# `CMD npm start` faz o npm ser o PID 1: ele recebe o SIGTERM e não repassa.
# O handler existe, está correto, e nunca é chamado.
for df in Dockerfile Dockerfile.prod docker/Dockerfile; do
  [ -f "$df" ] || continue
  L=$(grep -nE '^[[:space:]]*(CMD|ENTRYPOINT)[[:space:]]*\[?[[:space:]]*"?(npm|yarn|pnpm)"?[[:space:],]' "$df" 2>/dev/null | head -1)
  [ -n "$L" ] && add_finding "med" \
    "Container inicia via gerenciador de pacote ($(trim_ws "$(printf '%s' "$L" | cut -d: -f2-)")) — o npm/yarn/pnpm vira PID 1, recebe o SIGTERM e não repassa ao processo filho. O handler existe e nunca é chamado. Chame o runtime direto (CMD [\"node\", \"src/server.js\"]) ou use um init (tini, docker run --init)." \
    "$df" "$(printf '%s' "$L" | cut -d: -f1)"
done

if [ "${#FINDINGS[@]}" -gt 0 ]; then
  emit_result "$BLINDAR_AGENT" "failed" 0
  exit 0
fi
emit_result "$BLINDAR_AGENT" "passed" 0
exit 0
