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
  # file/line TAMBÉM passam por escape_json: no Windows o rg emite paths com
  # barra invertida (src\config.ts) e "\c" não é escape JSON válido → o result
  # ficava impossível de parsear justamente quando o check ACHAVA algo.
  local f=$(printf '{"severity":"%s","message":"%s","file":"%s","line":"%s"}' \
    "$sev" "$(escape_json "$msg")" "$(escape_json "$file")" "$(escape_json "$line")")
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

  # skipped por falta de ferramenta é DIFERENTE de skipped por não se aplicar.
  # O primeiro é ausência de cobertura e não pode ser lido como aprovação —
  # quem consome o result precisa conseguir distinguir os dois.
  local skip_json="null"
  [ -n "${BLINDAR_MISSING_TOOL:-}" ] && skip_json="\"$(escape_json "$BLINDAR_MISSING_TOOL")\""

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
  "missing_tool": $skip_json,
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

# ─── Tipos customizados do ripgrep ───
# 'prisma' e 'env' NÃO existem no ripgrep, mas o fallback de grep abaixo os
# mapeia. Sem isto, `--type prisma ` faz o rg REAL sair com erro 2 ("unrecognized
# file type"), a saída vem vazia, o `|| true` mascara, e o check reporta passed.
# Definir centralmente aqui garante que os dois caminhos concordem.
# NÃO usar RIPGREP_CONFIG_PATH aqui: no Git Bash o valor sai em forma POSIX
# (/c/Users/...), o rg.exe é nativo e não abre esse caminho — ele erra em TODA
# invocação ("failed to read the file specified in RIPGREP_CONFIG_PATH").
# Os tipos customizados são injetados pelo wrapper abaixo, que não depende de
# config externa nem pode ser sobrescrito pelo operador.

# ─── TMPDIR em forma nativa (Git Bash / MSYS) ───
# Os checks usam $(mktemp), que devolve /tmp/tmp.XXXX. Como o wrapper desliga a
# conversão de argumentos do MSYS (necessário pra que padrões iniciados por '/'
# cheguem intactos), o rg.exe nativo passaria a NÃO conseguir abrir esses
# arquivos: "IO error ... os error 2", saída vazia, detecção muda. Apontar o
# TMPDIR pra forma mista (C:/...) resolve os dois lados de uma vez.
if [ -z "${BLINDAR_TMPDIR_SET:-}" ] && command -v cygpath >/dev/null 2>&1; then
  _blindar_tmp="$(cygpath -m /tmp 2>/dev/null || true)"
  if [ -n "$_blindar_tmp" ] && [ -d "$_blindar_tmp" ]; then
    export TMPDIR="$_blindar_tmp"
    export BLINDAR_TMPDIR_SET=1
  fi
  unset _blindar_tmp
fi

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
# ─── Tipos customizados, iguais nos DOIS caminhos ───
# 'prisma' e 'env' não existem no ripgrep, mas o fallback de grep abaixo os
# mapeia (linhas 'prisma)' e 'env)'). Sem isto, `--type prisma ` faz o rg REAL
# sair com erro 2 ("unrecognized file type"), a saída vem vazia, o `|| true`
# mascara, e o check reporta passed. Wrapper em vez de RIPGREP_CONFIG_PATH:
# config global pode ser sobrescrita pelo operador; wrapper não.
# ─── STDIN: o rg REAL lê stdin quando ele NÃO é tty e nenhum path foi passado ───
# Todos os checks chamam `rg PADRAO --type ts ...` SEM path, contando que o rg
# varra o diretório atual. Isso só vale quando stdin é um tty. Se o check roda com
# stdin em pipe/arquivo (execFileSync stdio:'pipe', CI, `run-all | tee`, cron,
# `bash check.sh < /dev/null` em runner), o rg passa a buscar NO STDIN vazio →
# zero matches → `|| echo 0` mascara → check reporta PASSED estando CEGO.
# `</dev/null` força stdin a um char device, que o rg não considera "buscável",
# então ele volta a varrer o cwd. Nenhum check pipa dados PRA dentro do rg
# (auditado: 0 ocorrências de `| rg` e `rg <<<`), então isto é seguro.
# O caminho de fallback (grep, abaixo) já resolvia isso com `paths=(".")`.
if type -P rg >/dev/null 2>&1; then
  BLINDAR_RG_BIN="$(type -P rg)"
  export BLINDAR_RG_BIN
  # ─── MSYS/Cygwin argv path-mangling (Git Bash no Windows) ───
  # rg.exe é binário NATIVO do Windows. Ao spawnar um nativo, o runtime MSYS
  # reescreve TODO argumento que "parece" caminho POSIX. Um padrão de URL como
  # "/health/live" ou "(/checkout|/cart)" vira "C:/Program Files/Git/health/live"
  # ANTES do rg ver — o regex nunca casa, saída vazia, `|| true` mascara → a
  # detecção some silenciosamente (o check acusa ausência de rota que EXISTE).
  # MSYS2_ARG_CONV_EXCL='*' desliga a conversão só para este processo; o rg aceita
  # barras normais em caminhos, então nada mais é afetado. Em Linux/macOS as vars
  # são ignoradas. Não passar caminho POSIX absoluto (/c/...) pro rg daqui.
  rg() {
    MSYS2_ARG_CONV_EXCL='*' MSYS_NO_PATHCONV=1 \
      command "$BLINDAR_RG_BIN" --type-add 'prisma:*.prisma' --type-add 'env:.env*' "$@" </dev/null
  }
  export -f rg
fi

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
# ─── Guarda de ferramenta obrigatória ───
# Ferramenta ausente NÃO pode virar "passed". Antes disto, um check que
# dependia de jq simplesmente não validava nada e reportava aprovado — e o
# check-termination chegava a declarar release-ready contando findings como
# string vazia. Aqui o check para, se marca como skipped POR FALTA DE
# FERRAMENTA (distinguível no JSON), e diz o que você perde e como resolver.
#
# Uso:  require_tool jq "validação do manifest e contagem de findings"
require_tool() {
  local tool="$1" perde="${2:-as validações deste check}"
  command -v "$tool" >/dev/null 2>&1 && return 0

  local hint
  case "$tool" in
    jq)   hint="winget install jqlang.jq   |   apt install jq   |   brew install jq" ;;
    rg)   hint="winget install BurntSushi.ripgrep.MSVC   |   apt install ripgrep   |   brew install ripgrep" ;;
    node) hint="https://nodejs.org (>=20)" ;;
    *)    hint="instale '$tool' e rode de novo" ;;
  esac

  log_fail "'$tool' não está instalado — SEM COBERTURA em: $perde"
  log_warn "instale com:  $hint"
  log_warn "este check NÃO reprovou; ele não conseguiu rodar. Não leia como aprovado."

  BLINDAR_MISSING_TOOL="$tool"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
}

# Variante NÃO-fatal: use quando a ferramenta gateia só UM bloco do check, não
# o check inteiro. Mata o bloco, registra o buraco como achado, e deixa o resto
# rodar. Abortar a etapa toda por causa de um bloco perde cobertura que existe.
#
# Uso:  if have_tool jq "paridade de chaves entre locales"; then ... fi
have_tool() {
  local tool="$1" perde="${2:-uma verificação deste check}"
  command -v "$tool" >/dev/null 2>&1 && return 0
  log_warn "'$tool' ausente — pulando: $perde (o resto do check continua)"
  add_finding "med" "Sem cobertura em '$perde': ferramenta '$tool' não instalada — isto é buraco de verificação, não aprovação" "" ""
  # Marca no result mesmo quando o check termina "passed": aprovado COM buraco
  # não pode ficar indistinguível de aprovado com cobertura completa. Acumula
  # se mais de uma ferramenta faltar.
  case ",${BLINDAR_MISSING_TOOL:-}," in
    *",$tool,"*) ;;
    *) BLINDAR_MISSING_TOOL="${BLINDAR_MISSING_TOOL:+$BLINDAR_MISSING_TOOL,}$tool" ;;
  esac
  return 1
}

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
