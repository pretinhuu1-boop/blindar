#!/usr/bin/env bash
# blindar smoke — VERDADE DE RUNTIME. Prova que a app SOBE e responde.
# É o maior furo histórico do blindar (checks estáticos diziam "verde" com a
# imagem sem bootar e vários 500). grep nunca pega boot-quebrado nem 500 de
# runtime (ex: slowapi sem response:Response, coluna NOT NULL não setada).
#
# Regra homolog (nunca dev): sobe com dados MOCK direto no banco, espelhando
# produção. Recusa config de dev. Ver check-homolog-only.sh.
#
# Uso:
#   bash scripts/smoke-run.sh [--url URL] [--health PATH] [--timeout SEC]
#                             [--compose FILE] [--flow auto|none] [--keep] [--json]
#
#   --url    : app já rodando (pula orquestração de container) — bom pra homolog remoto
#   default  : sobe docker compose (homolog), espera health, roda fluxo, derruba
#
# Fluxo crítico: se existir .blindar/smoke-flow.sh, roda ele (fluxo custom tipo
# signup→login→GET protegido). Senão, varre os GET externos do grafo e flag 5xx.
#
# Exit 0 = subiu e respondeu. Exit 1 = boot quebrado ou 500 de runtime.

BLINDAR_AGENT="check-smoke-runtime"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../templates/checks/_lib.sh"
log_section "Smoke: verdade de runtime (boot + health + fluxo)"

URL=""; HEALTH=""; TIMEOUT=60; COMPOSE=""; FLOW="auto"; KEEP=0; JSON=0
while [ $# -gt 0 ]; do
  case "$1" in
    --url) URL="$2"; shift 2 ;;
    --health) HEALTH="$2"; shift 2 ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    --compose) COMPOSE="$2"; shift 2 ;;
    --flow) FLOW="$2"; shift 2 ;;
    --keep) KEEP=1; shift ;;
    --json) JSON=1; shift ;;
    *) shift ;;
  esac
done

command -v curl >/dev/null 2>&1 || { log_warn "curl ausente — smoke skipped"; emit_result "$BLINDAR_AGENT" "skipped" 0; exit 0; }

# ─── Garante o grafo (reusa Fase 1; constrói se faltar) ───
GRAPH=".blindar/graph.json"
if [ ! -f "$GRAPH" ] && command -v node >/dev/null 2>&1 && [ -f "$SCRIPT_DIR/graph-build.js" ]; then
  node "$SCRIPT_DIR/graph-build.js" --dir . >/dev/null 2>&1 || true
fi

ORCHESTRATED=0
teardown() {
  [ "$ORCHESTRATED" -eq 1 ] && [ "$KEEP" -eq 0 ] || return 0
  log_info "Derrubando containers do smoke..."
  docker compose -f "$COMPOSE" down -v >/dev/null 2>&1 || true
}
trap teardown EXIT

# ─── Sobe a app (homolog) se --url não foi dado ───
if [ -z "$URL" ]; then
  if ! command -v docker >/dev/null 2>&1; then
    log_warn "docker ausente e sem --url — smoke skipped (rode com --url pra homolog remoto)"
    emit_result "$BLINDAR_AGENT" "skipped" 0; exit 0
  fi
  if [ -z "$COMPOSE" ]; then
    for c in docker-compose.homolog.yml compose.homolog.yml docker-compose.yml compose.yml; do
      [ -f "$c" ] && { COMPOSE="$c"; break; }
    done
  fi
  if [ -z "$COMPOSE" ]; then
    log_warn "nenhum docker-compose encontrado e sem --url — smoke skipped"
    emit_result "$BLINDAR_AGENT" "skipped" 0; exit 0
  fi
  log_info "Subindo homolog via $COMPOSE (dados mock, espelho de produção — nunca dev)..."
  # Homolog: mock no banco, config espelho de prod. NUNCA NODE_ENV=development.
  export BLINDAR_ENV=homolog
  [ "${NODE_ENV:-}" = "development" ] && export NODE_ENV=production
  if ! docker compose -f "$COMPOSE" up -d --build >/dev/null 2>&1; then
    add_finding "crit" "docker compose up falhou — a app não constrói/sobe (boot quebrado)" "$COMPOSE" ""
    emit_result "$BLINDAR_AGENT" "failed" 1; exit 1
  fi
  ORCHESTRATED=1
  # Porta exposta do grafo → URL (fallback localhost:3000)
  PORT=$(node -e "try{const g=require('./.blindar/graph.json');const s=g.nodes.find(n=>n.type==='service'&&n.exposed);process.stdout.write(process.env.BLINDAR_SMOKE_PORT||'3000')}catch(e){process.stdout.write('3000')}" 2>/dev/null || echo 3000)
  URL="http://localhost:${PORT}"
fi

log_info "Alvo: $URL"

# ─── Espera health ───
HEALTH_PATHS=()
[ -n "$HEALTH" ] && HEALTH_PATHS+=("$HEALTH")
HEALTH_PATHS+=("/health/ready" "/healthz" "/readyz" "/health" "/api/health" "/")
HEALTHY=""
DEADLINE=$(( $(date +%s) + TIMEOUT ))
while [ "$(date +%s)" -lt "$DEADLINE" ]; do
  for p in "${HEALTH_PATHS[@]}"; do
    code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "${URL}${p}" 2>/dev/null || echo 000)
    if [ "$code" = "200" ] || [ "$code" = "204" ]; then HEALTHY="$p"; break; fi
  done
  [ -n "$HEALTHY" ] && break
  sleep 2
done

if [ -z "$HEALTHY" ]; then
  add_finding "crit" "app não respondeu health em ${TIMEOUT}s (boot quebrado ou health ausente) — tentado: ${HEALTH_PATHS[*]}" "" ""
  emit_result "$BLINDAR_AGENT" "failed" 1
  exit 1
fi
log_pass "health OK em ${URL}${HEALTHY}"

# ─── Fluxo crítico ───
FAIL=0
if [ "$FLOW" != "none" ] && [ -f ".blindar/smoke-flow.sh" ]; then
  log_info "Rodando fluxo crítico custom: .blindar/smoke-flow.sh"
  if ! SMOKE_URL="$URL" bash .blindar/smoke-flow.sh; then
    add_finding "high" "fluxo crítico custom (.blindar/smoke-flow.sh) falhou" "" ""
    FAIL=1
  fi
elif [ "$FLOW" != "none" ] && [ -f "$GRAPH" ] && command -v node >/dev/null 2>&1; then
  # Varre GET externos sem params → qualquer 5xx é 500 de runtime.
  ENDPOINTS=$(node -e "
    try{const g=require('./.blindar/graph.json');
    const eps=g.nodes.filter(n=>n.type==='endpoint'&&!n.internal&&n.method==='GET'&&!n.path.includes(':')&&!n.path.includes('{'));
    console.log([...new Set(eps.map(e=>e.path))].slice(0,15).join('\n'));}catch(e){}" 2>/dev/null)
  if [ -n "$ENDPOINTS" ]; then
    while IFS= read -r ep; do
      [ -z "$ep" ] && continue
      code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 8 "${URL}${ep}" 2>/dev/null || echo 000)
      if [ "${code:0:1}" = "5" ]; then
        add_finding "high" "GET $ep retornou $code — 500 de runtime (grep nunca pega)" "" ""
        FAIL=1
      fi
    done <<< "$ENDPOINTS"
    log_info "Varredura de GET externos concluída"
  fi
fi

if [ "$FAIL" -eq 1 ]; then emit_result "$BLINDAR_AGENT" "failed" 1; exit 1; fi
emit_result "$BLINDAR_AGENT" "passed" 0
exit 0
