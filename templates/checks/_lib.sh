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

# ─── rg fallback (grep) quando ripgrep não está instalado como BINÁRIO ───
# Detecta rg BINÁRIO real (type -P ignora função/alias do shell — command -v não basta).
# Emula ripgrep sobre grep com FIDELIDADE aos flags usados pelos checks. Bugs
# históricos corrigidos aqui (ver docs/CHECK-BUGS-AUDIT.md):
#   • flags agrupados (-cE, -nE, -lE, -niE, -hoE, -ciE...) eram descartados no
#     catch-all → check passava sem detectar. Agora normalizados char-a-char.
#   • `-c` mapeava pra `grep -rc` que lista arquivos com contagem :0 → `| wc -l`
#     contava TODOS os arquivos, não os com match. Agora filtra `:0` (igual rg -c).
#   • `-n` era descartado → checks que fazem `IFS=: read file line content`
#     recebiam content na var line → parsing quebrado. Agora `-n` vira grep -n.
if ! type -P rg >/dev/null 2>&1; then
  rg() {
    # Isola erros do grep — pipefail/errexit do caller não devem matar o wrapper.
    set +eo pipefail
    local includes=() excludes=() grepflags=() paths=() pattern=""
    local want_count=0 fixed=0
    while [ $# -gt 0 ]; do
      case "$1" in
        --type)
          case "$2" in
            ts)   includes+=(--include='*.ts' --include='*.tsx' --include='*.cts' --include='*.mts') ;;
            tsx)  includes+=(--include='*.tsx') ;;
            js)   includes+=(--include='*.js' --include='*.jsx' --include='*.mjs' --include='*.cjs') ;;
            jsx)  includes+=(--include='*.jsx') ;;
            json) includes+=(--include='*.json') ;;
            yml|yaml) includes+=(--include='*.yml' --include='*.yaml') ;;
            html) includes+=(--include='*.html' --include='*.htm') ;;
            md)   includes+=(--include='*.md') ;;
            env)  includes+=(--include='.env*') ;;
            py)   includes+=(--include='*.py') ;;
            go)   includes+=(--include='*.go') ;;
            rust|rs) includes+=(--include='*.rs') ;;
            css)  includes+=(--include='*.css' --include='*.scss') ;;
            sh)   includes+=(--include='*.sh' --include='*.bash') ;;
            dockerfile) includes+=(--include='Dockerfile*') ;;
            prisma) includes+=(--include='*.prisma') ;;
            sql)  includes+=(--include='*.sql') ;;
            tf)   includes+=(--include='*.tf') ;;
          esac
          shift 2 ;;
        -g|--glob)
          # -g '!glob' → exclude ; -g 'glob' → include
          local g="$2"
          if [[ "$g" == '!'* ]]; then
            g="${g#!}"; g="${g#\*\*/}"; g="${g%/\*\*}"
            if [[ "$g" == *\** ]]; then excludes+=(--exclude="${g##*/}")
            else excludes+=(--exclude-dir="$g"); fi
          else
            includes+=(--include="${g##*/}")
          fi
          shift 2 ;;
        -A) grepflags+=(-A "$2"); shift 2 ;;
        -B) grepflags+=(-B "$2"); shift 2 ;;
        -C) grepflags+=(-C "$2"); shift 2 ;;
        '!'*)
          # Forma antiga (IGNORE posicional). Suportada por compat.
          local p="${1#!}"; p="${p#\*\*/}"; p="${p%/\*\*}"
          if [[ "$p" == *\** ]]; then excludes+=(--exclude="${p##*/}")
          else excludes+=(--exclude-dir="$p"); fi
          shift ;;
        --) shift ;;
        -[a-zA-Z]*)
          # Bundle de short flags — processa char a char. 'E' é no-op (grep já -E).
          local bundle="${1#-}" ch i=0
          while [ "$i" -lt "${#bundle}" ]; do
            ch="${bundle:$i:1}"
            case "$ch" in
              c) want_count=1 ;;
              l) grepflags+=(-l) ;;
              n) grepflags+=(-n) ;;
              o) grepflags+=(-o) ;;
              i) grepflags+=(-i) ;;
              w) grepflags+=(-w) ;;
              v) grepflags+=(-v) ;;
              h) grepflags+=(-h) ;;
              q) grepflags+=(-q) ;;
              F) fixed=1 ;;
              E) : ;;
              *) : ;;
            esac
            i=$((i+1))
          done
          shift ;;
        *)
          if [ -z "$pattern" ]; then pattern="$1"; else paths+=("$1"); fi
          shift ;;
      esac
    done
    [ -z "$pattern" ] && return 0
    # Sem path → busca o diretório atual. NÃO tentamos ler stdin: detectar "pipe
    # pra rg" via /dev/stdin também casa quando o PRÓPRIO check é chamado com stdin
    # em pipe (execFileSync/pipeline) → rg leria o pipe vazio e não acharia nada.
    # Checks que precisam filtrar um pipe usam `| grep`, não `| rg`.
    [ ${#paths[@]} -eq 0 ] && paths=(".")
    local base=(-r --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=dist --exclude-dir=.blindar)
    if [ "$fixed" -eq 1 ]; then base+=(-F); else base+=(-E); fi
    if [ "$want_count" -eq 1 ]; then
      # rg -c: só arquivos COM match. grep -rc emite contagem 0 (formato "path:0"
      # em multi-arquivo, ou "0" puro em arquivo único) → awk descarta zeros.
      grep "${base[@]}" -c "${grepflags[@]}" "${includes[@]}" "${excludes[@]}" -- "$pattern" "${paths[@]}" 2>/dev/null | awk -F: '($NF+0)>0'
      return 0
    fi
    grep "${base[@]}" "${grepflags[@]}" "${includes[@]}" "${excludes[@]}" -- "$pattern" "${paths[@]}" 2>/dev/null
    # Retorna o exit REAL do grep (0=match, 1=sem match, 2=erro) — igual ripgrep.
    return $?
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
  # Compat legada. A supressão por-agente real é via load_intelligence_globs (abaixo).
  return 1
}

# ─── Intelligence globs (v0.45): exclusões POR AGENTE de .blindar/intelligence.yml ───
# Deixa o operador suprimir falso-positivo por check SEM editar o check. Formato:
#   ignore_globs:
#     check-cors-csrf:
#       - "legacy/**"
#     all:                 # aplica a todos os checks
#       - "**/*.generated.*"
# Popula o array global INTEL_GLOBS com pares "-g '!<glob>'". Zero deps (awk POSIX;
# \047 = aspa simples, evita inferno de escape). Os checks anexam "${INTEL_GLOBS[@]}"
# às chamadas rg (via scripts/wire-intel-globs.js).
INTEL_GLOBS=()
load_intelligence_globs() {
  local agent="$1"
  INTEL_GLOBS=()
  local yml="${BLINDAR_DIR:-.blindar}/intelligence.yml"
  [ -f "$yml" ] || return 0
  local g
  while IFS= read -r g; do
    [ -z "$g" ] && continue
    INTEL_GLOBS+=(-g "!$g")
  done < <(awk -v agent="$agent" '
    /^[[:space:]]*#/ { next }
    /^ignore_globs:[[:space:]]*$/ { insec=1; next }
    insec && /^[^[:space:]]/ { insec=0 }
    insec {
      if ($0 ~ /^  [A-Za-z0-9_.*-]+:[[:space:]]*$/) { key=$0; sub(/^  /,"",key); sub(/:.*$/,"",key); cur=key; next }
      if ($0 ~ /^    +-[[:space:]]*/) { line=$0; sub(/^ *- */,"",line); gsub(/^[\047"]|[\047"]$/,"",line); gsub(/[[:space:]]+$/,"",line); if (cur==agent || cur=="all") print line }
    }
  ' "$yml" 2>/dev/null)
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
