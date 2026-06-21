#!/usr/bin/env bash
# blindar checks — biblioteca compartilhada
# Source este arquivo no início de cada check:  source "$(dirname "$0")/_lib.sh"

set -euo pipefail

BLINDAR_DIR="${BLINDAR_DIR:-.blindar}"
RESULTS_DIR="${RESULTS_DIR:-$BLINDAR_DIR/results}"
mkdir -p "$RESULTS_DIR"

# ─── Cores (CI-aware) ───
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'
  BLUE='\033[0;34m'; BOLD='\033[1m'; RESET='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; BLUE=''; BOLD=''; RESET=''
fi

# ─── Logging ───
log_info()    { echo "${BLUE}ℹ${RESET}  $*"; }
log_pass()    { echo "${GREEN}✓${RESET}  $*"; }
log_warn()    { echo "${YELLOW}⚠${RESET}  $*"; }
log_fail()    { echo "${RED}✗${RESET}  $*" >&2; }
log_section() { echo ""; echo "${BOLD}═══ $* ═══${RESET}"; }

# ─── Findings array (acumula no script) ───
declare -a FINDINGS=()

add_finding() {
  local sev="$1"; local msg="$2"; local file="${3:-}"; local line="${4:-}"
  local f=$(printf '{"severity":"%s","message":"%s","file":"%s","line":"%s"}' \
    "$sev" "$(escape_json "$msg")" "$file" "$line")
  FINDINGS+=("$f")
}

escape_json() {
  echo -n "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/	/\\t/g; s/$/\\n/g' | tr -d '\n' | sed 's/\\n$//'
}

# ─── Output JSON padrão por check ───
emit_result() {
  local agent="$1"; local status="$2"  # passed|failed|skipped
  local exit_code="${3:-0}"
  local started="${STARTED_AT:-$(date -u +%s)}"
  local duration=$(( $(date -u +%s) - started ))
  local sha=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
  local findings_json="["$(IFS=,; echo "${FINDINGS[*]:-}")"]"

  local out="$RESULTS_DIR/${agent}.json"
  cat > "$out" <<EOF
{
  "schema": "blindar/check-result@v1",
  "agent": "$agent",
  "ran_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "git_sha": "$sha",
  "status": "$status",
  "exit_code": $exit_code,
  "duration_sec": $duration,
  "findings_count": ${#FINDINGS[@]},
  "findings": $findings_json
}
EOF

  log_info "Resultado: $out"
  case "$status" in
    passed) log_pass "$agent PASSED" ;;
    failed) log_fail "$agent FAILED (${#FINDINGS[@]} findings)" ;;
    skipped) log_warn "$agent SKIPPED" ;;
  esac
}

# ─── Detecção de stack ───
has_file() { [ -f "$1" ]; }
has_dir()  { [ -d "$1" ]; }

is_nodejs()  { has_file "package.json"; }
is_python()  { has_file "pyproject.toml" || has_file "requirements.txt" || has_file "Pipfile"; }
is_go()      { has_file "go.mod"; }
is_rust()    { has_file "Cargo.toml"; }
is_prisma()  { has_file "prisma/schema.prisma"; }
is_nextjs()  { has_file "next.config.js" || has_file "next.config.ts" || has_file "next.config.mjs"; }
is_nestjs()  { has_file "nest-cli.json"; }

# ─── Skip via intelligence.yml ───
check_ignored_by_intelligence() {
  local agent="$1"; local file_or_pattern="$2"
  # Stub: leitura real do .blindar/intelligence.yml ficaria aqui.
  # Por enquanto retorna sempre falso (não pula nada). Operador pode estender.
  return 1
}

# ─── Pegar começo de timestamp ───
STARTED_AT=$(date -u +%s)

# ─── Trap pra exit handler ───
on_error() {
  log_fail "Check abortado por erro inesperado"
  emit_result "${BLINDAR_AGENT:-unknown}" "failed" "$?"
}
trap on_error ERR
