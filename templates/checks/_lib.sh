#!/usr/bin/env bash
# blindar checks — biblioteca compartilhada
# Source este arquivo no início de cada check:  source "$(dirname "$0")/_lib.sh"

# ─── Bash version check (warn, não fail) ───
# blindar usa principalmente sintaxe compatível com bash 3.2 (macOS default),
# mas algumas features (declare -a, fallback rg) são mais robustas em bash 4+.
# Veja docs/BASH-COMPAT.md pra detalhes e instruções de upgrade no macOS.
if [ -n "${BASH_VERSION:-}" ] && [ "${BASH_VERSINFO[0]}" -lt 4 ] && [ -z "${BLINDAR_BASH_WARN_SHOWN:-}" ]; then
  echo "⚠ blindar foi testado em bash 4+ (você tem $BASH_VERSION). Pode haver bugs sutis — veja docs/BASH-COMPAT.md" >&2
  export BLINDAR_BASH_WARN_SHOWN=1
fi

# Não usar pipefail nem errexit — checks fazem rg|grep|sort pipelines onde
# rg sem match (exit 1) NÃO é erro. Cada check decide localmente seu controle.
set -uo pipefail
set +e +o pipefail

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

# ─── rg fallback (grep -rE) quando binário ausente ───
# Detecta se rg está como BINÁRIO real (não função do shell). type -P só pega arquivos.
if ! type -P rg >/dev/null 2>&1; then
  # Define função `rg` que traduz flags comuns pra grep -rE.
  # Suporta: -n, -c, -i, -E, -A N, -B N, --type ts/tsx/js/jsx/json/yml/html/md/env,
  # padrões !path como excludes, e pattern posicional.
  rg() {
    # Isola erros do grep — pipefail/errexit do caller não devem matar o wrapper
    set +eo pipefail
    local includes=() excludes=() flags=("-rE") pattern="" path="." after=0 before=0 count_only=0
    while [ $# -gt 0 ]; do
      case "$1" in
        -n|-E) shift ;;
        -i) flags+=("-i"); shift ;;
        -c) flags+=("-c"); count_only=1; shift ;;
        -nE|-En) shift ;;
        -ni|-in|-niE|-inE|-nEi|-Eni|-iEn|-Ein) flags+=("-i"); shift ;;
        -nc|-cn) flags+=("-c"); count_only=1; shift ;;
        -A) flags+=("-A" "$2"); shift 2 ;;
        -B) flags+=("-B" "$2"); shift 2 ;;
        -nA) flags+=("-A" "$2"); shift 2 ;;
        -nB) flags+=("-B" "$2"); shift 2 ;;
        -l|-nl|-ln) flags+=("-l"); shift ;;
        --type)
          case "$2" in
            ts)   includes+=(--include='*.ts' --include='*.tsx' --include='*.cts' --include='*.mts') ;;
            tsx)  includes+=(--include='*.tsx') ;;
            js)   includes+=(--include='*.js' --include='*.jsx' --include='*.mjs' --include='*.cjs') ;;
            jsx)  includes+=(--include='*.jsx') ;;
            json) includes+=(--include='*.json') ;;
            yml|yaml) includes+=(--include='*.yml' --include='*.yaml') ;;
            html) includes+=(--include='*.html') ;;
            md)   includes+=(--include='*.md') ;;
            env)  includes+=(--include='.env*') ;;
          esac
          shift 2 ;;
        '!'*)
          local p="${1#!}"
          # Estratégia: pra **/X/** ou X/** → exclude-dir X
          #             pra **/*.ext → exclude *.ext
          #             pra simples sem * → exclude-dir
          # Tira leading **/
          [[ "$p" == \*\*/* ]] && p="${p#\*\*/}"
          # Tira trailing /**
          [[ "$p" == */\*\* ]] && p="${p%/\*\*}"
          # Se sobra * no path → é glob arquivo (--exclude)
          # Se não tem * → é dir (--exclude-dir)
          if [[ "$p" == *\** ]]; then
            # Pega só o basename
            excludes+=(--exclude="${p##*/}")
          else
            excludes+=(--exclude-dir="$p")
          fi
          shift ;;
        --) shift ;;
        -*) shift ;;
        *)
          if [ -z "$pattern" ]; then pattern="$1"
          else path="$1"; fi
          shift ;;
      esac
    done
    [ -z "$pattern" ] && return 0
    grep "${flags[@]}" "${includes[@]}" "${excludes[@]}" -- "$pattern" "$path" 2>/dev/null
    local rc=$?
    # grep retorna 1 quando não acha match — não é erro. retorna 2 em erro real.
    [ $rc -eq 1 ] && return 0
    return $rc
  }
  export -f rg
fi

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

# ─── NOTA: `trap on_error ERR` foi REMOVIDO de propósito ───
# `trap ERR` só dispara quando `set -e` (errexit) está ativo. Como esta
# biblioteca explicitamente desliga errexit acima (`set +e +o pipefail`)
# pra permitir pipelines com rg/grep sem match (exit 1 ≠ erro), o trap
# era código morto: nunca disparava.
#
# Não recolocar sem antes reativar errexit — o que quebraria a maioria
# dos checks. Cada check é responsável por gerenciar seus próprios
# erros via `emit_result` (status passed|failed|skipped) e add_finding.
