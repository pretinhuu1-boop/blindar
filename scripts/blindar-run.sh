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
#   bash scripts/blindar-run.sh [opts]
#
#   --strict          Falha se algum agente está só como playbook (sem .sh nem .api.sh)
#   --fast            Roda módulos críticos incluindo segurança e supply-chain
#                     (módulos 1, 2, 5, 11, 12, 15)
#   --security-only   Roda APENAS módulos de segurança: 2 (core security),
#                     5 (supply-chain), 15 (pentest). Mutex com --module.
#   --module N,N,N    Lista módulos por número (ex: --module 1,2,9)
#   --json            Output JSON puro pra CI
#   --with-evolution  Encadeia blindar-evolve.sh após hardening
#   --since REF       Modo diff: roda checks só sobre arquivos mudados desde REF
#                     (ex: --since HEAD~1, --since main, --since <SHA>)
#                     Exporta BLINDAR_CHANGED_FILES pros checks consumirem.
#                     Sai 0 se nenhum arquivo mudou.
#   --parallel N      Roda checks em paralelo (N workers). Default 1.
#                     Use --parallel auto pra detectar CPUs (fallback 4).
#   --verbose         Preserva stdout/stderr dos checks (prefixado com agente).
#                     Sem ela, output é silenciado (comportamento atual).
#
# Pré-requisitos:
#   - bash 4+, grep, sed (POSIX)
#   - Node 20+ (pra parsear MODULE-MAP)
#   - jq OU node (auto-fallback)
#   - ANTHROPIC_API_KEY (opcional, só pra wrappers API)
#   - git (opcional, só pra --since)

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
SKILL_VERSION="$(tr -d '[:space:]' < "$SKILL_DIR/VERSION" 2>/dev/null || echo unknown)"

mkdir -p "$RESULTS_DIR"

# Parse args
STRICT=0; FAST=0; SECURITY_ONLY=0; JSON_ONLY=0; MODULES_FILTER=""; WITH_EVOLUTION=0
SINCE_REF=""; PARALLEL="1"; VERBOSE=0; NO_PROACTIVE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --strict) STRICT=1; shift ;;
    --fast)   FAST=1; shift ;;
    --security-only) SECURITY_ONLY=1; shift ;;
    --json)   JSON_ONLY=1; shift ;;
    --module) MODULES_FILTER="$2"; shift 2 ;;
    --with-evolution) WITH_EVOLUTION=1; shift ;;
    --since)  SINCE_REF="$2"; shift 2 ;;
    --parallel) PARALLEL="$2"; shift 2 ;;
    --verbose|-v) VERBOSE=1; shift ;;
    --no-proactive) NO_PROACTIVE=1; shift ;;
    -h|--help) sed -n '2,40p' "$0" | sed 's/^# //; s/^#//'; exit 0 ;;
    *) echo "Arg desconhecido: $1" >&2; exit 64 ;;
  esac
done

# Permite desligar via env var também
[ "${BLINDAR_SKIP_PROACTIVE:-0}" = "1" ] && NO_PROACTIVE=1

# Mutex: --security-only não pode coexistir com --module
if [ "$SECURITY_ONLY" -eq 1 ] && [ -n "$MODULES_FILTER" ]; then
  echo "ERRO: --security-only é mutex com --module" >&2
  exit 64
fi

# Resolve --parallel auto → nproc/sysctl, fallback 4
if [ "$PARALLEL" = "auto" ]; then
  if command -v nproc >/dev/null 2>&1; then
    PARALLEL=$(nproc 2>/dev/null || echo 4)
  elif command -v sysctl >/dev/null 2>&1; then
    PARALLEL=$(sysctl -n hw.ncpu 2>/dev/null || echo 4)
  else
    PARALLEL=4
  fi
fi
# Sanitize: precisa ser inteiro positivo
case "$PARALLEL" in
  ''|*[!0-9]*) PARALLEL=1 ;;
esac
[ "$PARALLEL" -lt 1 ] && PARALLEL=1

if [ -t 1 ] && [ "$JSON_ONLY" -eq 0 ]; then
  R=$'\e[31m'; G=$'\e[32m'; Y=$'\e[33m'; B=$'\e[34m'; BOLD=$'\e[1m'; RST=$'\e[0m'
else R=''; G=''; Y=''; B=''; BOLD=''; RST=''; fi

log() { [ "$JSON_ONLY" -eq 0 ] && echo "$@" >&2; }
log_section() { log ""; log "${BOLD}═══ $* ═══${RST}"; }

# ─── FEATURE 1: --since (diff mode) ─────────────────────────────────────────
CHANGED_FILES=""
CHANGED_FILES_JSON="[]"
if [ -n "$SINCE_REF" ]; then
  if ! command -v git >/dev/null 2>&1; then
    echo "${R}ERRO: --since requer git${RST}" >&2
    exit 73
  fi
  if ! git rev-parse --git-dir >/dev/null 2>&1; then
    echo "${R}ERRO: --since requer estar em repo git${RST}" >&2
    exit 73
  fi
  if ! git rev-parse --verify "$SINCE_REF" >/dev/null 2>&1; then
    echo "${R}ERRO: ref '$SINCE_REF' não existe${RST}" >&2
    exit 73
  fi
  CHANGED_FILES=$(git diff --name-only "$SINCE_REF"...HEAD 2>/dev/null || true)
  # Inclui também working tree changes (uncommitted) opcionalmente — só committed por enquanto
  if [ -z "$CHANGED_FILES" ]; then
    log "${Y}no changes since $SINCE_REF — nothing to check${RST}"
    # Ainda escreve um report mínimo
    cat > "$RUN_REPORT" <<EOF
{
  "schema": "blindar/run-report@v1",
  "skill_version": "$SKILL_VERSION",
  "ran_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "duration_sec": 0,
  "since": "$SINCE_REF",
  "changed_files": [],
  "total_agents": 0,
  "passed": 0, "failed": 0, "skipped": 0, "deferred": 0, "errored": 0,
  "coverage_pct": 100,
  "message": "no changes since $SINCE_REF",
  "results": []
}
EOF
    exit 0
  fi
  export BLINDAR_CHANGED_FILES="$CHANGED_FILES"
  export BLINDAR_SINCE_REF="$SINCE_REF"
  # Monta JSON array dos arquivos mudados
  CHANGED_FILES_JSON=$(printf '%s\n' "$CHANGED_FILES" | node -e "
    const lines=require('fs').readFileSync(0,'utf8').split('\n').filter(Boolean);
    process.stdout.write(JSON.stringify(lines));
  ")
  CHANGED_COUNT=$(printf '%s\n' "$CHANGED_FILES" | grep -c .)
  log "${B}--since $SINCE_REF${RST} → $CHANGED_COUNT arquivo(s) mudado(s)"
fi

# Extrai lista de agentes do MODULE-MAP (Node — sempre disponível)
if ! command -v node >/dev/null 2>&1; then
  echo "${R}ERRO: Node.js 20+ requerido${RST}" >&2
  exit 70
fi

[ ! -f "$MODULE_MAP" ] && { echo "${R}MODULE-MAP.json não encontrado em $MODULE_MAP${RST}" >&2; exit 71; }

# fast mode: módulos 1,2,5,11,12,15 (críticos + supply-chain).
# security-only: apenas 2 (core security), 5 (supply-chain), 15 (pentest).
# Manual: o que veio em --module.
if [ "$SECURITY_ONLY" -eq 1 ]; then
  FILTER="2,5,15"
  log_section "Security-only mode — rodando módulos 2 (core security), 5 (supply-chain), 15 (pentest)"
elif [ -n "$MODULES_FILTER" ]; then
  FILTER="$MODULES_FILTER"
elif [ "$FAST" -eq 1 ]; then
  FILTER="1,2,5,11,12,15"
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
log_section "blindar-run: $TOTAL agentes (modules=$FILTER, strict=$STRICT, parallel=$PARALLEL, verbose=$VERBOSE${SINCE_REF:+, since=$SINCE_REF})"

TOTAL_START=$(date +%s)

# ─── Função: roda 1 check (usada tanto serial quanto em paralelo) ───────────
# Args: $1=module_id  $2=agent
# Lê: CHECKS_DIR, RESULTS_DIR, VERBOSE, JSON_ONLY (env)
# Escreve: result_json (já feito pelo próprio check) + linha no stdout no formato:
#   "module|agent|kind|status|findings"
# Logs vão pro stderr.
run_one_check() {
  local module_id="$1"
  local agent="$2"
  local det="$CHECKS_DIR/check-${agent}.sh"
  local api="$CHECKS_DIR/check-${agent}.api.sh"
  local result_json="$RESULTS_DIR/check-${agent}.json"
  local kind script status findings rc

  if [ -f "$det" ]; then
    kind="deterministic"; script="$det"
  elif [ -f "$api" ]; then
    kind="api-wrapped"; script="$api"
  else
    kind="playbook-only"; script=""
  fi

  if [ -z "$script" ]; then
    [ "$JSON_ONLY" -eq 0 ] && echo "${Y}⏭${RST}  $agent (module $module_id) — playbook-only, requer Claude" >&2
    cat > "$result_json" <<EOF
{"schema":"blindar/check-result@v1","agent":"check-$agent","status":"deferred","kind":"playbook-only","module":"$module_id","findings_count":0,"findings":[],"message":"Agente disponível só como playbook em agents/$agent.md — requer Claude pra executar"}
EOF
    echo "$module_id|$agent|$kind|deferred|0"
    return 0
  fi

  [ "$JSON_ONLY" -eq 0 ] && echo "${B}▶${RST}  $agent (module $module_id, $kind)..." >&2

  # Remove resultado de run anterior: se o check morrer sem escrever, o status
  # vira "errored" em vez de reler um JSON stale como se fosse desta execução.
  rm -f "$result_json" 2>/dev/null || true

  if [ "$VERBOSE" -eq 1 ]; then
    # Preserva stdout/stderr, prefixa com nome do agente
    bash "$script" 2>&1 | sed "s/^/  [$agent] /" >&2
    rc=${PIPESTATUS[0]}
  else
    bash "$script" >/dev/null 2>&1
    rc=$?
  fi

  if [ -f "$result_json" ]; then
    status=$(grep -oE '"status"[[:space:]]*:[[:space:]]*"[a-z]+"' "$result_json" | head -1 | sed -E 's/.*"([a-z]+)".*/\1/')
    findings=$(grep -oE '"findings_count"[[:space:]]*:[[:space:]]*[0-9]+' "$result_json" | head -1 | sed -E 's/.*:[[:space:]]*([0-9]+).*/\1/')
    [ -z "$findings" ] && findings=0
  else
    status="errored"; findings=0
  fi

  local ico
  case "$status" in
    passed)  ico="${G}✓${RST}" ;;
    failed)  ico="${R}✗${RST}" ;;
    skipped) ico="${Y}⏭${RST}" ;;
    deferred) ico="${Y}⏭${RST}" ;;
    *) ico="${R}!${RST}"; status="errored" ;;
  esac
  [ "$JSON_ONLY" -eq 0 ] && echo "$ico  $agent → $status ($findings findings)" >&2
  echo "$module_id|$agent|$kind|$status|$findings"
  return 0
}
export -f run_one_check 2>/dev/null || true

# ─── Execução: serial ou paralela ───────────────────────────────────────────
declare -a RESULTS=()
RUN_LOG="$RESULTS_DIR/.run-lines.log"
: > "$RUN_LOG"

if [ "$PARALLEL" -gt 1 ]; then
  # Modo paralelo: usa xargs -P. Cada worker chama bash -c que invoca run_one_check.
  # Exportar variáveis necessárias pros subshells:
  export CHECKS_DIR RESULTS_DIR VERBOSE JSON_ONLY R G Y B BOLD RST

  # Cria um script-helper inline temporário pra invocar run_one_check com env passada
  HELPER=$(mktemp 2>/dev/null || echo "$RESULTS_DIR/.parallel-helper.sh")
  cat > "$HELPER" <<'HELPER_EOF'
#!/usr/bin/env bash
set -uo pipefail
line="$1"
module_id="${line%%:*}"
agent="${line#*:}"
[ -z "$agent" ] && exit 0

det="$CHECKS_DIR/check-${agent}.sh"
api="$CHECKS_DIR/check-${agent}.api.sh"
result_json="$RESULTS_DIR/check-${agent}.json"

if [ -f "$det" ]; then kind="deterministic"; script="$det"
elif [ -f "$api" ]; then kind="api-wrapped"; script="$api"
else kind="playbook-only"; script=""
fi

if [ -z "$script" ]; then
  [ "${JSON_ONLY:-0}" -eq 0 ] && echo "${Y}⏭${RST}  $agent (module $module_id) — playbook-only, requer Claude" >&2
  cat > "$result_json" <<EOF2
{"schema":"blindar/check-result@v1","agent":"check-$agent","status":"deferred","kind":"playbook-only","module":"$module_id","findings_count":0,"findings":[],"message":"Agente disponível só como playbook em agents/$agent.md — requer Claude pra executar"}
EOF2
  echo "$module_id|$agent|$kind|deferred|0"
  exit 0
fi

[ "${JSON_ONLY:-0}" -eq 0 ] && echo "${B}▶${RST}  $agent (module $module_id, $kind)..." >&2

# Anti-stale: mesmo contrato do modo serial
rm -f "$result_json" 2>/dev/null || true

if [ "${VERBOSE:-0}" -eq 1 ]; then
  bash "$script" 2>&1 | sed "s/^/  [$agent] /" >&2
else
  bash "$script" >/dev/null 2>&1
fi

if [ -f "$result_json" ]; then
  status=$(grep -oE '"status"[[:space:]]*:[[:space:]]*"[a-z]+"' "$result_json" | head -1 | sed -E 's/.*"([a-z]+)".*/\1/')
  findings=$(grep -oE '"findings_count"[[:space:]]*:[[:space:]]*[0-9]+' "$result_json" | head -1 | sed -E 's/.*:[[:space:]]*([0-9]+).*/\1/')
  [ -z "$findings" ] && findings=0
else
  status="errored"; findings=0
fi

case "$status" in
  passed)  ico="${G}✓${RST}" ;;
  failed)  ico="${R}✗${RST}" ;;
  skipped) ico="${Y}⏭${RST}" ;;
  deferred) ico="${Y}⏭${RST}" ;;
  *) ico="${R}!${RST}"; status="errored" ;;
esac
[ "${JSON_ONLY:-0}" -eq 0 ] && echo "$ico  $agent → $status ($findings findings)" >&2
echo "$module_id|$agent|$kind|$status|$findings"
HELPER_EOF
  chmod +x "$HELPER" 2>/dev/null || true

  # Dispara xargs -P. Output (linha por agente) vai pra RUN_LOG.
  printf '%s\n' "$AGENTS_LIST" | grep . | \
    xargs -I{} -P "$PARALLEL" bash "$HELPER" "{}" >> "$RUN_LOG" || true

  rm -f "$HELPER" 2>/dev/null || true
else
  # Modo serial (loop original, agora via função)
  while IFS=: read -r module_id agent; do
    [ -z "$agent" ] && continue
    run_one_check "$module_id" "$agent" >> "$RUN_LOG"
  done <<< "$AGENTS_LIST"
fi

# Agrega resultados lendo o log
PASSED=0; FAILED=0; SKIPPED=0; DEFERRED=0; ERRORED=0
while IFS='|' read -r mid ag kind st fc; do
  [ -z "$ag" ] && continue
  case "$st" in
    passed)   PASSED=$((PASSED+1))   ;;
    failed)   FAILED=$((FAILED+1))   ;;
    skipped)  SKIPPED=$((SKIPPED+1)) ;;
    deferred) DEFERRED=$((DEFERRED+1)) ;;
    *)        ERRORED=$((ERRORED+1)); st="errored" ;;
  esac
  RESULTS+=("$mid|$ag|$kind|$st|$fc")
done < "$RUN_LOG"

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
  echo "  \"skill_version\": \"$SKILL_VERSION\","
  echo "  \"ran_at\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
  echo "  \"duration_sec\": $DURATION,"
  echo "  \"modules_filter\": \"$FILTER\","
  echo "  \"strict_mode\": $STRICT,"
  echo "  \"parallel\": $PARALLEL,"
  echo "  \"verbose\": $VERBOSE,"
  if [ -n "$SINCE_REF" ]; then
    echo "  \"since\": \"$SINCE_REF\","
    echo "  \"changed_files\": $CHANGED_FILES_JSON,"
  fi
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

# ─── Cost summary (token governor) ─────────────────────────────────────
# Se _token_governor.sh foi usado por qualquer wrapper API, mostra total $.
GOVERNOR="$CHECKS_DIR/_token_governor.sh"
if [ -f "$GOVERNOR" ] && [ -f "${BLINDAR_DIR:-$PROJECT_DIR/.blindar}/cost.log" ]; then
  source "$GOVERNOR" 2>/dev/null && {
    SUMMARY=$(blindar_cost_summary 2>/dev/null)
    [ -n "$SUMMARY" ] && log "$SUMMARY"
  }
fi

# ─── Validação de schemas (opcional, NÃO falha o run) ───────────────────────
# Se houver node + validate-schemas.js + schemas/, roda uma checagem leve.
# Output: 1 linha resumo. Inválidos viram warning, não erro.
VALIDATOR="$SKILL_DIR/scripts/validate-schemas.js"
if command -v node >/dev/null 2>&1 && [ -f "$VALIDATOR" ] && [ -d "$SKILL_DIR/schemas" ]; then
  VAL_OUT=$(node "$VALIDATOR" --input "$RESULTS_DIR" --quiet 2>&1 || true)
  if echo "$VAL_OUT" | grep -q "^✓"; then
    log "${G}✓ Schemas válidos${RST}"
  elif echo "$VAL_OUT" | grep -q "^⚠"; then
    BAD_COUNT=$(echo "$VAL_OUT" | grep -oE '^⚠ [0-9]+' | grep -oE '[0-9]+' | head -1)
    log "${Y}⚠ ${BAD_COUNT:-?} arquivo(s) com schema inválido${RST} (rode: node \"$VALIDATOR\" --input \"$RESULTS_DIR\")"
  fi
fi

# ─── Análise proativa (auto se ANTHROPIC_API_KEY) ───
if [ "$NO_PROACTIVE" -eq 0 ] && [ -n "${ANTHROPIC_API_KEY:-}" ] && [ -f "$CHECKS_DIR/check-proactive-analysis.api.sh" ]; then
  log ""
  log_section "Análise proativa (8 dimensões)"
  bash "$CHECKS_DIR/check-proactive-analysis.api.sh" 2>&1 | tail -5
  if [ -f "${BLINDAR_DIR:-$PROJECT_DIR/.blindar}/proactive-analysis.md" ]; then
    log "Relatório consultivo: ${BLINDAR_DIR:-$PROJECT_DIR/.blindar}/proactive-analysis.md"
  fi
fi

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
