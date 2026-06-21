#!/usr/bin/env bash
# blindar-run.sh — ORQUESTRADOR ÚNICO. Esta é a forma garantida de rodar blindar.
#
# Itera todos os agentes do MODULE-MAP. Pra cada um:
#   1. Procura check-<agent>.sh (determinístico)
#   2. Se não acha, procura check-<agent>.api.sh (wrapper Claude API)
#   3. Se não acha nenhum: marca como "deferred-to-claude" no relatório
#
# Saída: .blindar/run-report.json com status de TODA a suite.
# Exit codes: 0=GO, 1=CONDITIONAL-GO, 2=NO-GO, 3=DEFERRED (precisa Claude)
#
# Uso:
#   bash scripts/blindar-run.sh [--strict] [--fast] [--module N,N,N] [--json]
#
#   --strict   Falha se algum agente está só como playbook (sem .sh nem .api.sh)
#   --fast     Roda só agentes críticos (módulos 1, 2, 11, 12, 15)
#   --module   Lista módulos por número (ex: --module 1,2,9)
#   --json     Output JSON puro pra CI
#
# Pré-requisitos:
#   - bash 4+, grep, sed (POSIX)
#   - Node 20+ (pra parsear MODULE-MAP)
#   - jq OU node (auto-fallback)
#   - ANTHROPIC_API_KEY (opcional, só pra wrappers API)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Descobre layout: skill (~/.claude/skills/blindar) OU instalado em projeto (scripts/)
if [ -d "$SCRIPT_DIR/../templates/checks" ]; then
  # Layout skill canonical
  SKILL_DIR="$(dirname "$SCRIPT_DIR")"
  CHECKS_DIR="$SKILL_DIR/templates/checks"
  MODULE_MAP="$SKILL_DIR/pipeline/MODULE-MAP.json"
elif [ -d "$SCRIPT_DIR/blindar" ]; then
  # Layout instalado: scripts/blindar/check-*.sh + scripts/blindar/pipeline/MODULE-MAP.json
  CHECKS_DIR="$SCRIPT_DIR/blindar"
  MODULE_MAP="$SCRIPT_DIR/blindar/pipeline/MODULE-MAP.json"
  SKILL_DIR="$SCRIPT_DIR"
else
  # Fallback: tenta encontrar via ~/.claude/skills/blindar
  if [ -d "$HOME/.claude/skills/blindar" ]; then
    SKILL_DIR="$HOME/.claude/skills/blindar"
    CHECKS_DIR="$SKILL_DIR/templates/checks"
    MODULE_MAP="$SKILL_DIR/pipeline/MODULE-MAP.json"
  else
    echo "ERRO: não consegui localizar checks/ nem MODULE-MAP.json" >&2
    echo "Esperava: $SCRIPT_DIR/../templates/ ou $SCRIPT_DIR/blindar/ ou ~/.claude/skills/blindar/" >&2
    exit 72
  fi
fi
PROJECT_DIR="${PWD}"
RESULTS_DIR="${BLINDAR_DIR:-$PROJECT_DIR/.blindar}/results"
RUN_REPORT="${BLINDAR_DIR:-$PROJECT_DIR/.blindar}/run-report.json"

mkdir -p "$RESULTS_DIR"

# Parse args
STRICT=0; FAST=0; JSON_ONLY=0; MODULES_FILTER=""; WITH_EVOLUTION=0
while [ $# -gt 0 ]; do
  case "$1" in
    --strict) STRICT=1; shift ;;
    --fast)   FAST=1; shift ;;
    --json)   JSON_ONLY=1; shift ;;
    --module) MODULES_FILTER="$2"; shift 2 ;;
    --with-evolution) WITH_EVOLUTION=1; shift ;;
    -h|--help) sed -n '2,25p' "$0" | sed 's/^# //'; exit 0 ;;
    *) echo "Arg desconhecido: $1" >&2; exit 64 ;;
  esac
done

if [ -t 1 ] && [ "$JSON_ONLY" -eq 0 ]; then
  R=$'\e[31m'; G=$'\e[32m'; Y=$'\e[33m'; B=$'\e[34m'; BOLD=$'\e[1m'; RST=$'\e[0m'
else R=''; G=''; Y=''; B=''; BOLD=''; RST=''; fi

log() { [ "$JSON_ONLY" -eq 0 ] && echo "$@" >&2; }
log_section() { log ""; log "${BOLD}═══ $* ═══${RST}"; }

# Extrai lista de agentes do MODULE-MAP (Node — sempre disponível)
if ! command -v node >/dev/null 2>&1; then
  echo "${R}ERRO: Node.js 20+ requerido${RST}" >&2
  exit 70
fi

[ ! -f "$MODULE_MAP" ] && { echo "${R}MODULE-MAP.json não encontrado em $MODULE_MAP${RST}" >&2; exit 71; }

# fast mode: módulos 1,2,11,12,15. Manual: o que veio em --module.
if [ -n "$MODULES_FILTER" ]; then
  FILTER="$MODULES_FILTER"
elif [ "$FAST" -eq 1 ]; then
  FILTER="1,2,11,12,15"
else
  FILTER="all"
fi

# Converte path POSIX (/c/...) pra Windows (C:\...) quando rodando Node Windows
MODULE_MAP_NATIVE="$MODULE_MAP"
if command -v cygpath >/dev/null 2>&1; then
  MODULE_MAP_NATIVE=$(cygpath -w "$MODULE_MAP")
fi

AGENTS_LIST=$(node -e "
const m = JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));
const filter = process.argv[2];
const ids = filter === 'all' ? Object.keys(m.modules) : filter.split(',');
const out = [];
ids.forEach(id => {
  const mod = m.modules[id];
  if (!mod) return;
  mod.agents.forEach(a => out.push(id + ':' + a));
});
console.log([...new Set(out)].join('\n'));
" "$MODULE_MAP_NATIVE" "$FILTER")

TOTAL=$(echo "$AGENTS_LIST" | grep -c .)
log_section "blindar-run: $TOTAL agentes (modules=$FILTER, strict=$STRICT)"

# Loop principal
declare -a RESULTS=()
PASSED=0; FAILED=0; SKIPPED=0; DEFERRED=0; ERRORED=0
TOTAL_START=$(date +%s)

while IFS=: read -r module_id agent; do
  [ -z "$agent" ] && continue

  det="$CHECKS_DIR/check-${agent}.sh"
  api="$CHECKS_DIR/check-${agent}.api.sh"
  result_json="$RESULTS_DIR/check-${agent}.json"

  if [ -f "$det" ]; then
    kind="deterministic"
    script="$det"
  elif [ -f "$api" ]; then
    kind="api-wrapped"
    script="$api"
  else
    kind="playbook-only"
    script=""
  fi

  if [ -z "$script" ]; then
    DEFERRED=$((DEFERRED+1))
    status="deferred"
    [ "$JSON_ONLY" -eq 0 ] && log "${Y}⏭${RST}  $agent (module $module_id) — playbook-only, requer Claude"
    cat > "$result_json" <<EOF
{"schema":"blindar/check-result@v1","agent":"check-$agent","status":"deferred","kind":"playbook-only","module":"$module_id","findings_count":0,"findings":[],"message":"Agente disponível só como playbook em agents/$agent.md — requer Claude pra executar"}
EOF
    RESULTS+=("$module_id|$agent|$kind|deferred|0")
    continue
  fi

  [ "$JSON_ONLY" -eq 0 ] && log "${B}▶${RST}  $agent (module $module_id, $kind)..."
  bash "$script" >/dev/null 2>&1
  rc=$?

  # Parse status do result.json
  if [ -f "$result_json" ]; then
    status=$(grep -oE '"status"[[:space:]]*:[[:space:]]*"[a-z]+"' "$result_json" | head -1 | sed -E 's/.*"([a-z]+)".*/\1/')
    findings=$(grep -oE '"findings_count"[[:space:]]*:[[:space:]]*[0-9]+' "$result_json" | head -1 | sed -E 's/.*:[[:space:]]*([0-9]+).*/\1/')
    [ -z "$findings" ] && findings=0
  else
    status="errored"
    findings=0
  fi

  case "$status" in
    passed)  PASSED=$((PASSED+1));  ico="${G}✓${RST}" ;;
    failed)  FAILED=$((FAILED+1));  ico="${R}✗${RST}" ;;
    skipped) SKIPPED=$((SKIPPED+1)); ico="${Y}⏭${RST}" ;;
    *)       ERRORED=$((ERRORED+1)); ico="${R}!${RST}"; status="errored" ;;
  esac
  [ "$JSON_ONLY" -eq 0 ] && log "$ico  $agent → $status ($findings findings)"
  RESULTS+=("$module_id|$agent|$kind|$status|$findings")
done <<< "$AGENTS_LIST"

DURATION=$(( $(date +%s) - TOTAL_START ))

# Strict mode: deferred = fail
if [ "$STRICT" -eq 1 ] && [ "$DEFERRED" -gt 0 ]; then
  log ""
  log "${R}${BOLD}STRICT MODE: $DEFERRED agente(s) sem forma executável${RST}"
fi

# Aggregate report
{
  echo "{"
  echo "  \"schema\": \"blindar/run-report@v1\","
  echo "  \"ran_at\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
  echo "  \"duration_sec\": $DURATION,"
  echo "  \"modules_filter\": \"$FILTER\","
  echo "  \"strict_mode\": $STRICT,"
  echo "  \"total_agents\": $TOTAL,"
  echo "  \"passed\": $PASSED,"
  echo "  \"failed\": $FAILED,"
  echo "  \"skipped\": $SKIPPED,"
  echo "  \"deferred\": $DEFERRED,"
  echo "  \"errored\": $ERRORED,"
  echo "  \"coverage_pct\": $(( (PASSED + FAILED + SKIPPED) * 100 / (TOTAL > 0 ? TOTAL : 1) )),"
  echo "  \"results\": ["
  first=1
  for r in "${RESULTS[@]}"; do
    IFS='|' read -r mid ag kind st fc <<< "$r"
    [ $first -eq 0 ] && echo ","
    first=0
    printf '    {"module":"%s","agent":"%s","kind":"%s","status":"%s","findings":%s}' "$mid" "$ag" "$kind" "$st" "$fc"
  done
  echo ""
  echo "  ]"
  echo "}"
} > "$RUN_REPORT"

[ "$JSON_ONLY" -eq 1 ] && cat "$RUN_REPORT" && exit 0

log ""
log_section "Resultado"
log "Duração: ${DURATION}s"
log "${G}Passed:${RST}   $PASSED"
log "${R}Failed:${RST}   $FAILED"
log "${Y}Skipped:${RST}  $SKIPPED"
log "${Y}Deferred:${RST} $DEFERRED (precisa Claude)"
log "${R}Errored:${RST}  $ERRORED"
log "Cobertura executável: $(( (PASSED + FAILED + SKIPPED) * 100 / (TOTAL > 0 ? TOTAL : 1) ))%"
log ""
log "Report: $RUN_REPORT"

# Captura exit code do hardening pra preservar
if [ "$ERRORED" -gt 0 ]; then HARDENING_EXIT=4
elif [ "$FAILED" -gt 0 ]; then HARDENING_EXIT=2
elif [ "$STRICT" -eq 1 ] && [ "$DEFERRED" -gt 0 ]; then HARDENING_EXIT=3
elif [ "$DEFERRED" -gt 0 ]; then HARDENING_EXIT=1
else HARDENING_EXIT=0; fi

# --with-evolution: invoca blindar-evolve.sh após hardening
if [ "$WITH_EVOLUTION" -eq 1 ]; then
  log ""
  log_section "Encadeando: blindar-evolve.sh (módulo 16)"
  EVOLVE_SCRIPT="$SCRIPT_DIR/blindar-evolve.sh"
  [ ! -f "$EVOLVE_SCRIPT" ] && EVOLVE_SCRIPT="$SKILL_DIR/scripts/blindar-evolve.sh"
  if [ -f "$EVOLVE_SCRIPT" ]; then
    bash "$EVOLVE_SCRIPT" || EVOL_RC=$?
    # Hardening exit code prevalece (gate de release); evolution é informativo
  else
    log "${Y}⚠${RST}  blindar-evolve.sh não encontrado — skip"
  fi
fi

exit "$HARDENING_EXIT"
