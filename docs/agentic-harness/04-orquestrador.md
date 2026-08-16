## `scripts/<NOME>-run.sh` — orquestrador único (esqueleto completo)

Inclui: auto-detect layout + paralelização + diff mode + verbose + with-evolution.

```bash
#!/usr/bin/env bash
# Orquestrador único. ENTRYPOINT MANDATÓRIO.
#
# Uso: bash scripts/<NOME>-run.sh [opts]
#
# Opções:
#   --strict          Falha se algum agente é só playbook (sem .sh/.api.sh)
#   --fast            Roda só módulos críticos
#   --module N,N,N    Lista módulos por número
#   --json            Output JSON puro pra CI
#   --since REF       Modo diff: git diff REF..HEAD → BLINDAR_CHANGED_FILES env
#   --parallel N      Roda checks em paralelo via xargs -P (auto = CPUs)
#   --verbose / -v    Preserva stdout dos checks (prefixado com [agent])
#   --with-evolution  Encadeia <NOME>-evolve.sh após hardening
#
# Exit codes: 0=PASS, 1=CONDITIONAL, 2=FAIL, 3=STRICT-FAIL, 4=ERRORED

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Auto-detect layout: skill canonical / instalado / fallback HOME
if [ -d "$SCRIPT_DIR/../templates/checks" ]; then
  SKILL_DIR="$(dirname "$SCRIPT_DIR")"
  CHECKS_DIR="$SKILL_DIR/templates/checks"
  MODULE_MAP="$SKILL_DIR/pipeline/MODULE-MAP.json"
elif [ -d "$SCRIPT_DIR/<NOME>" ]; then
  CHECKS_DIR="$SCRIPT_DIR/<NOME>"
  MODULE_MAP="$SCRIPT_DIR/<NOME>/pipeline/MODULE-MAP.json"
  SKILL_DIR="$SCRIPT_DIR"
elif [ -d "$HOME/.claude/skills/<NOME>" ]; then
  SKILL_DIR="$HOME/.claude/skills/<NOME>"
  CHECKS_DIR="$SKILL_DIR/templates/checks"
  MODULE_MAP="$SKILL_DIR/pipeline/MODULE-MAP.json"
else
  echo "ERRO: não consegui localizar checks/" >&2
  exit 72
fi

PROJECT_DIR="${PWD}"
RESULTS_DIR="${BLINDAR_DIR:-$PROJECT_DIR/.<NOME>}/results"
RUN_REPORT="${BLINDAR_DIR:-$PROJECT_DIR/.<NOME>}/run-report.json"
mkdir -p "$RESULTS_DIR"

# Parse args
STRICT=0; FAST=0; JSON_ONLY=0; MODULES_FILTER=""; WITH_EVOLUTION=0
SINCE_REF=""; PARALLEL="1"; VERBOSE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --strict) STRICT=1; shift ;;
    --fast)   FAST=1; shift ;;
    --json)   JSON_ONLY=1; shift ;;
    --module) MODULES_FILTER="$2"; shift 2 ;;
    --with-evolution) WITH_EVOLUTION=1; shift ;;
    --since)  SINCE_REF="$2"; shift 2 ;;
    --parallel) PARALLEL="$2"; shift 2 ;;
    --verbose|-v) VERBOSE=1; shift ;;
    -h|--help) sed -n '2,20p' "$0" | sed 's/^# //; s/^#//'; exit 0 ;;
    *) echo "Arg desconhecido: $1" >&2; exit 64 ;;
  esac
done

# --parallel auto → detecta CPUs
if [ "$PARALLEL" = "auto" ]; then
  if command -v nproc >/dev/null 2>&1; then PARALLEL=$(nproc 2>/dev/null || echo 4)
  elif command -v sysctl >/dev/null 2>&1; then PARALLEL=$(sysctl -n hw.ncpu 2>/dev/null || echo 4)
  else PARALLEL=4; fi
fi
case "$PARALLEL" in ''|*[!0-9]*) PARALLEL=1 ;; esac
[ "$PARALLEL" -lt 1 ] && PARALLEL=1

# Colors
if [ -t 1 ] && [ "$JSON_ONLY" -eq 0 ]; then
  R=$'\e[31m'; G=$'\e[32m'; Y=$'\e[33m'; B=$'\e[34m'; BOLD=$'\e[1m'; RST=$'\e[0m'
else R=''; G=''; Y=''; B=''; BOLD=''; RST=''; fi

log() { [ "$JSON_ONLY" -eq 0 ] && echo "$@" >&2; }
log_section() { log ""; log "${BOLD}═══ $* ═══${RST}"; }

# --since: git diff + exporta env
CHANGED_FILES=""
CHANGED_FILES_JSON="[]"
if [ -n "$SINCE_REF" ]; then
  command -v git >/dev/null 2>&1 || { echo "ERRO: --since requer git" >&2; exit 73; }
  git rev-parse --git-dir >/dev/null 2>&1 || { echo "ERRO: requer repo git" >&2; exit 73; }
  git rev-parse --verify "$SINCE_REF" >/dev/null 2>&1 || { echo "ERRO: ref '$SINCE_REF' inexistente" >&2; exit 73; }
  CHANGED_FILES=$(git diff --name-only "$SINCE_REF"...HEAD 2>/dev/null || true)
  if [ -z "$CHANGED_FILES" ]; then
    log "${Y}no changes since $SINCE_REF — nothing to check${RST}"
    cat > "$RUN_REPORT" <<EOF
{"schema":"<NS>/run-report@v1","ran_at":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","since":"$SINCE_REF","total_agents":0,"passed":0,"failed":0,"skipped":0,"deferred":0,"errored":0,"coverage_pct":100,"message":"no changes","results":[]}
EOF
    exit 0
  fi
  export BLINDAR_CHANGED_FILES="$CHANGED_FILES"
  export BLINDAR_SINCE_REF="$SINCE_REF"
  CHANGED_FILES_JSON=$(printf '%s\n' "$CHANGED_FILES" | node -e "
    const lines=require('fs').readFileSync(0,'utf8').split('\n').filter(Boolean);
    process.stdout.write(JSON.stringify(lines));
  ")
fi

command -v node >/dev/null 2>&1 || { echo "ERRO: Node.js 20+ requerido" >&2; exit 70; }
[ ! -f "$MODULE_MAP" ] && { echo "ERRO: $MODULE_MAP não encontrado" >&2; exit 71; }

# Fast mode: ajustar conforme sua skill
if [ -n "$MODULES_FILTER" ]; then FILTER="$MODULES_FILTER"
elif [ "$FAST" -eq 1 ]; then FILTER="1,2,11,12,15"
else FILTER="all"; fi

# Windows path fix
MODULE_MAP_NATIVE="$MODULE_MAP"
command -v cygpath >/dev/null 2>&1 && MODULE_MAP_NATIVE=$(cygpath -w "$MODULE_MAP")

AGENTS_LIST=$(node -e "
  const m = JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));
  const filter = process.argv[2];
  const ids = filter === 'all' ? Object.keys(m.modules) : filter.split(',');
  const out = [];
  ids.forEach(id => {
    const mod = m.modules[id]; if (!mod) return;
    mod.agents.forEach(a => out.push(id + ':' + a));
  });
  console.log([...new Set(out)].join('\n'));
" "$MODULE_MAP_NATIVE" "$FILTER")

TOTAL=$(echo "$AGENTS_LIST" | grep -c .)
log_section "<NOME>-run: $TOTAL agentes (modules=$FILTER, parallel=$PARALLEL${SINCE_REF:+, since=$SINCE_REF})"

TOTAL_START=$(date +%s)

# ─── Função: roda 1 check (serial ou xargs -P) ───
run_one_check() {
  local module_id="$1"; local agent="$2"
  local det="$CHECKS_DIR/check-${agent}.sh"
  local api="$CHECKS_DIR/check-${agent}.api.sh"
  local result_json="$RESULTS_DIR/check-${agent}.json"

  if [ -f "$det" ]; then kind="deterministic"; script="$det"
  elif [ -f "$api" ]; then kind="api-wrapped"; script="$api"
  else kind="playbook-only"; script=""; fi

  if [ -z "$script" ]; then
    cat > "$result_json" <<EOF
{"schema":"<NS>/check-result@v1","agent":"check-$agent","status":"deferred","kind":"playbook-only","module":"$module_id","findings_count":0,"findings":[]}
EOF
    echo "$module_id|$agent|$kind|deferred|0" >> "$RESULTS_DIR/.run-lines.log"
    log "${Y}⏭${RST}  $agent (module $module_id) — playbook-only"
    return
  fi

  log "${B}▶${RST}  $agent (module $module_id, $kind)..."
  if [ "$VERBOSE" -eq 1 ]; then
    bash "$script" 2>&1 | sed "s/^/  [$agent] /"
  else
    bash "$script" >/dev/null 2>&1
  fi

  local status findings
  if [ -f "$result_json" ]; then
    status=$(grep -oE '"status"[[:space:]]*:[[:space:]]*"[a-z]+"' "$result_json" | head -1 | sed -E 's/.*"([a-z]+)".*/\1/')
    findings=$(grep -oE '"findings_count"[[:space:]]*:[[:space:]]*[0-9]+' "$result_json" | head -1 | sed -E 's/.*:[[:space:]]*([0-9]+).*/\1/')
    [ -z "$findings" ] && findings=0
  else
    status="errored"; findings=0
  fi
  echo "$module_id|$agent|$kind|$status|$findings" >> "$RESULTS_DIR/.run-lines.log"

  local ico
  case "$status" in
    passed)  ico="${G}✓${RST}" ;;
    failed)  ico="${R}✗${RST}" ;;
    skipped) ico="${Y}⏭${RST}" ;;
    *)       ico="${R}!${RST}" ;;
  esac
  log "$ico  $agent → $status ($findings findings)"
}
export -f run_one_check log
export CHECKS_DIR RESULTS_DIR VERBOSE JSON_ONLY R G Y B BOLD RST

# Limpa log
> "$RESULTS_DIR/.run-lines.log"

# Executa serial ou paralelo
if [ "$PARALLEL" -gt 1 ]; then
  echo "$AGENTS_LIST" | tr ':' '\t' | xargs -P "$PARALLEL" -n 2 bash -c 'run_one_check "$0" "$1"'
else
  while IFS=: read -r mid ag; do
    [ -z "$ag" ] && continue
    run_one_check "$mid" "$ag"
  done <<< "$AGENTS_LIST"
fi

# Agrega contadores via log file (não usa vars bash — evita race)
PASSED=0; FAILED=0; SKIPPED=0; DEFERRED=0; ERRORED=0
declare -a RESULTS=()
while IFS='|' read -r mid ag kind st fc; do
  RESULTS+=("$mid|$ag|$kind|$st|$fc")
  case "$st" in
    passed)   PASSED=$((PASSED+1)) ;;
    failed)   FAILED=$((FAILED+1)) ;;
    skipped)  SKIPPED=$((SKIPPED+1)) ;;
    deferred) DEFERRED=$((DEFERRED+1)) ;;
    *)        ERRORED=$((ERRORED+1)) ;;
  esac
done < "$RESULTS_DIR/.run-lines.log"
rm -f "$RESULTS_DIR/.run-lines.log"

DURATION=$(( $(date +%s) - TOTAL_START ))

# Gera run-report.json
{
  echo "{"
  echo "  \"schema\": \"<NS>/run-report@v1\","
  echo "  \"ran_at\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
  echo "  \"duration_sec\": $DURATION,"
  echo "  \"modules_filter\": \"$FILTER\","
  echo "  \"strict_mode\": $STRICT,"
  echo "  \"parallel\": $PARALLEL,"
  echo "  \"verbose\": $VERBOSE,"
  [ -n "$SINCE_REF" ] && echo "  \"since\": \"$SINCE_REF\","
  [ -n "$SINCE_REF" ] && echo "  \"changed_files\": $CHANGED_FILES_JSON,"
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
log "Report: $RUN_REPORT"

# Validação schema (não-blocking — só warn)
VALIDATOR="$SKILL_DIR/scripts/validate-schemas.js"
if command -v node >/dev/null 2>&1 && [ -f "$VALIDATOR" ]; then
  if node "$VALIDATOR" --input "$RESULTS_DIR" --quiet 2>/dev/null; then
    log "${G}✓${RST} Schemas válidos"
  else
    log "${Y}⚠${RST}  Algum schema inválido — rode: node $VALIDATOR --input $RESULTS_DIR"
  fi
fi

# Captura exit code do hardening
if [ "$ERRORED" -gt 0 ]; then HARDENING_EXIT=4
elif [ "$FAILED" -gt 0 ]; then HARDENING_EXIT=2
elif [ "$STRICT" -eq 1 ] && [ "$DEFERRED" -gt 0 ]; then HARDENING_EXIT=3
elif [ "$DEFERRED" -gt 0 ]; then HARDENING_EXIT=1
else HARDENING_EXIT=0; fi

# --with-evolution: encadeia evolução
if [ "$WITH_EVOLUTION" -eq 1 ]; then
  log ""
  log_section "Encadeando: <NOME>-evolve.sh"
  EVOLVE_SCRIPT="$SCRIPT_DIR/<NOME>-evolve.sh"
  [ ! -f "$EVOLVE_SCRIPT" ] && EVOLVE_SCRIPT="$SKILL_DIR/scripts/<NOME>-evolve.sh"
  [ -f "$EVOLVE_SCRIPT" ] && bash "$EVOLVE_SCRIPT" || true
fi

exit "$HARDENING_EXIT"
```

---

