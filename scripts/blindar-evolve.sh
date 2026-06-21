#!/usr/bin/env bash
# blindar-evolve.sh — auditoria de PRODUTO (não código).
#
# Roda módulo 16 (Product Evolution) separado do core blindar-run.
# Gera .blindar/evolution-report.md com:
#   - APIs sem front-end
#   - Funcionalidades parciais
#   - Jornadas por perfil + fricções
#   - Oportunidades de crescimento (ordenadas por ROI)
#   - Críticas adversariais de produto
#   - Roadmap recomendado
#
# REQUER ANTHROPIC_API_KEY (todos 5 agentes são API-wrapped).
#
# Uso:
#   bash scripts/blindar-evolve.sh [--json]

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Detecta layout (mesma lógica do blindar-run.sh)
if [ -d "$SCRIPT_DIR/../templates/checks" ]; then
  SKILL_DIR="$(dirname "$SCRIPT_DIR")"
  CHECKS_DIR="$SKILL_DIR/templates/checks"
elif [ -d "$SCRIPT_DIR/blindar" ]; then
  CHECKS_DIR="$SCRIPT_DIR/blindar"
elif [ -d "$HOME/.claude/skills/blindar" ]; then
  CHECKS_DIR="$HOME/.claude/skills/blindar/templates/checks"
else
  echo "ERRO: blindar não encontrado" >&2
  exit 72
fi

PROJECT_DIR="${PWD}"
EVOLUTION_DIR="${BLINDAR_DIR:-$PROJECT_DIR/.blindar}/evolution"
RESULTS_DIR="${BLINDAR_DIR:-$PROJECT_DIR/.blindar}/results"
EVOLUTION_REPORT="${BLINDAR_DIR:-$PROJECT_DIR/.blindar}/evolution-report.md"

mkdir -p "$EVOLUTION_DIR" "$RESULTS_DIR"

JSON_ONLY=0
[ "${1:-}" = "--json" ] && JSON_ONLY=1

if [ -t 1 ] && [ "$JSON_ONLY" -eq 0 ]; then
  R=$'\e[31m'; G=$'\e[32m'; Y=$'\e[33m'; B=$'\e[34m'; BOLD=$'\e[1m'; RST=$'\e[0m'
else R=''; G=''; Y=''; B=''; BOLD=''; RST=''; fi

log() { [ "$JSON_ONLY" -eq 0 ] && echo "$@" >&2; }

# Pré-requisitos
if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
  log "${R}${BOLD}ANTHROPIC_API_KEY ausente.${RST}"
  log "Este orquestrador roda 5 agentes Claude API. Defina a key:"
  log "  export ANTHROPIC_API_KEY=sk-ant-..."
  exit 65
fi

log ""
log "${BOLD}═══ blindar-evolve: auditoria de produto ═══${RST}"
log ""
log "Output: $EVOLUTION_REPORT"
log "Agentes (todos via Claude API):"
log "  1. api-frontend-coverage"
log "  2. user-journey-simulator"
log "  3. feature-gap-analyzer"
log "  4. growth-opportunities"
log "  5. product-critic"
log ""

# Roda strategic-scanner primeiro (gera scan.json usado pelos outros)
if [ -f "$CHECKS_DIR/check-strategic-scanner.sh" ] && [ ! -f "${BLINDAR_DIR:-.blindar}/scan.json" ]; then
  log "${B}▶${RST}  strategic-scanner (pre-flight)..."
  bash "$CHECKS_DIR/check-strategic-scanner.sh" >/dev/null 2>&1
fi

# Roda os 5 agentes em sequência
AGENTS=(
  "api-frontend-coverage"
  "user-journey-simulator"
  "feature-gap-analyzer"
  "growth-opportunities"
  "product-critic"
)

declare -a AGENT_RESULTS=()
TOTAL_START=$(date +%s)

for agent in "${AGENTS[@]}"; do
  script="$CHECKS_DIR/check-${agent}.api.sh"
  if [ ! -f "$script" ]; then
    log "${Y}⏭${RST}  $agent — script não encontrado"
    AGENT_RESULTS+=("$agent|missing|0")
    continue
  fi
  log "${B}▶${RST}  $agent..."
  bash "$script" >/dev/null 2>&1
  result_json="$RESULTS_DIR/check-${agent}.json"
  if [ -f "$result_json" ]; then
    status=$(grep -oE '"status"[[:space:]]*:[[:space:]]*"[a-z]+"' "$result_json" | head -1 | sed -E 's/.*"([a-z]+)".*/\1/')
    findings=$(grep -oE '"findings_count"[[:space:]]*:[[:space:]]*[0-9]+' "$result_json" | head -1 | sed -E 's/.*:[[:space:]]*([0-9]+).*/\1/')
    [ -z "$findings" ] && findings=0
    case "$status" in
      passed)  ico="${G}✓${RST}" ;;
      failed)  ico="${R}✗${RST}" ;;
      skipped) ico="${Y}⏭${RST}" ;;
      *)       ico="${Y}?${RST}"; status="unknown" ;;
    esac
    log "$ico  $agent → $status ($findings findings)"
    AGENT_RESULTS+=("$agent|$status|$findings")
  else
    log "${R}!${RST}  $agent — sem result"
    AGENT_RESULTS+=("$agent|errored|0")
  fi
done

DURATION=$(( $(date +%s) - TOTAL_START ))

# Gera report markdown consolidado
{
  echo "# Blindar — Evolution Report"
  echo ""
  echo "Gerado em: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "Duração: ${DURATION}s"
  echo ""
  echo "## Sumário"
  echo ""
  echo "| Agente | Status | Findings |"
  echo "|---|---|---|"
  for r in "${AGENT_RESULTS[@]}"; do
    IFS='|' read -r ag st fc <<< "$r"
    echo "| $ag | $st | $fc |"
  done
  echo ""

  for agent in "${AGENTS[@]}"; do
    result_json="$RESULTS_DIR/check-${agent}.json"
    [ ! -f "$result_json" ] && continue
    echo ""
    echo "## $agent"
    echo ""
    # Lista findings via Node (parse JSON)
    if command -v node >/dev/null 2>&1; then
      node -e "
        try {
          const r = JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));
          if (!r.findings || r.findings.length === 0) {
            console.log('Sem findings (passed/skipped).');
            return;
          }
          const order = {crit:0, high:1, med:2, low:3};
          r.findings.sort((a,b) => (order[a.severity]??9) - (order[b.severity]??9));
          r.findings.forEach(f => {
            console.log('### [' + f.severity.toUpperCase() + '] ' + f.message);
            if (f.file) console.log('- **Local**: \`' + f.file + (f.line ? ':' + f.line : '') + '\`');
            if (f.fix) console.log('- **Fix**: ' + f.fix);
            console.log('');
          });
        } catch (e) { console.log('(erro lendo: ' + e.message + ')'); }
      " "$result_json"
    else
      grep -oE '"message":"[^"]*"' "$result_json" | sed 's/"message":"/- /;s/"$//'
    fi
  done

  echo ""
  echo "## Roadmap recomendado"
  echo ""
  echo "Sugerimos priorizar em ondas:"
  echo ""
  echo "1. **Correções críticas** (crit/high de qualquer agente)"
  echo "2. **Lacunas funcionais** (feature-gap-analyzer)"
  echo "3. **APIs sem UI** (api-frontend-coverage)"
  echo "4. **Fricções de UX** (user-journey-simulator + product-critic)"
  echo "5. **Diferenciais competitivos** (growth-opportunities ordenadas por ROI)"
  echo ""
  echo "---"
  echo ""
  echo "Gerado por blindar v$(cat ${SCRIPT_DIR}/../VERSION 2>/dev/null || echo unknown)."
} > "$EVOLUTION_REPORT"

log ""
log "${BOLD}═══ Concluído ═══${RST}"
log "Duração: ${DURATION}s"
log "Relatório: $EVOLUTION_REPORT"
log ""

[ "$JSON_ONLY" -eq 1 ] && {
  echo "{\"schema\":\"blindar/evolution@v1\",\"duration_sec\":$DURATION,\"agents\":$(printf '%s\n' "${AGENT_RESULTS[@]}" | jq -R 'split("|")|{agent:.[0],status:.[1],findings:(.[2]|tonumber)}' 2>/dev/null | jq -s . 2>/dev/null || echo '[]'),\"report\":\"$EVOLUTION_REPORT\"}"
}
exit 0
