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

# Apara espaço em volta e colapsa espaço interno.
#
# Substitui o idioma `$(echo "$x" | xargs)`, que estava em 38 lugares e fazia
# DUAS coisas erradas com o conteúdo varrido do projeto-alvo:
#
#   1. xargs INTERPRETA aspas. `if (x === "admin")` virava `if (x === admin)` —
#      a mensagem do finding mostrava código adulterado, sem as aspas que são
#      justamente o que importa numa comparação de string.
#   2. Aspa não fechada (comum em trecho cortado por `cut`) faz o xargs gritar
#      "unmatched double quote" e devolver a linha truncada. Um único run contra
#      projeto real produziu 466 desses.
#
# `tr`+`sed` não interpretam nada: tratam a entrada como texto, que é o que ela é.
trim_ws() {
  printf '%s' "$1" | tr -s '[:space:]' ' ' | sed -e 's/^ //' -e 's/ $//'
}

# Severidade fora do enum é finding INVISÍVEL. Todo consumidor casa a string
# exata: check-termination conta `.findings_by_severity.crit`, o release-gate
# faz `select(.severity=="crit")`, o check-evidence testa `=== "crit"`. Um
# add_finding com "critical" (em vez de "crit") produz um achado que aparece no
# JSON, não é contado por ninguém, e deixa o portão de release dizer GO com um
# crítico aberto.
# Encontrado em produção: check-healthtech-fhir e check-govtech-acessibilidade
# emitiam "critical", e check-ecom/fintech emitiam "medium".
#
# Normaliza os apelidos conhecidos. Valor desconhecido NÃO vira "low": o default
# do desconhecido nunca pode ser o valor benigno — vira "high" com o original
# preservado na mensagem, para aparecer e ser diagnosticável.
normalize_severity() {
  case "$1" in
    crit|high|med|low) echo "$1" ;;
    critical)          echo "crit" ;;
    medium|warning|warn) echo "med" ;;
    info|informational|note) echo "low" ;;
    *)                 echo "high" ;;
  esac
}

add_finding() {
  local sev="$1"; local msg="$2"; local file="${3:-}"; local line="${4:-}"
  local norm; norm=$(normalize_severity "$sev")
  if [ "$norm" != "$sev" ]; then
    case "$sev" in
      critical|medium|warning|warn|info|informational|note) : ;;
      *) msg="$msg [severidade inválida '$sev' recebida como high]" ;;
    esac
    sev="$norm"
  fi
  # file/line TAMBÉM passam por escape_json: no Windows o rg emite paths com
  # barra invertida (src\config.ts) e "\c" não é escape JSON válido → o result
  # ficava impossível de parsear justamente quando o check ACHAVA algo.
  local f=$(printf '{"severity":"%s","message":"%s","file":"%s","line":"%s"}' \
    "$sev" "$(escape_json "$msg")" "$(escape_json "$file")" "$(escape_json "$line")")
  FINDINGS+=("$f")
}

escape_json() {
  # Codificador JSON de string COMPLETO (RFC 8259 §7): escapa \ " e TODO
  # caractere de controle U+0000–U+001F. Antes, um `sed` cobria só \ " tab e
  # newline; um \r (saída CRLF do rg no Windows), \f, \b ou 0x01 vindo do
  # projeto-alvo passava cru → JSON inválido → `jq -s` do run-all falhava e
  # SUBSTITUÍA o aggregate inteiro (o alvo apagava o próprio relatório com 1
  # byte). awk POSIX/GNU (já dependência do fallback de rg), sem jq. Bytes
  # >= 0x80 (UTF-8 multibyte) passam intactos — JSON aceita UTF-8. `printf '%s'`
  # em vez de `echo -n` para não comer mensagem iniciada por -e/-n nem \ .
  # `bs` é a barra montada por código (sprintf %c 92) para não colidir com o
  # lexer de escape \u do gawk moderno em literais de string.
  printf '%s' "$1" | LC_ALL=C awk '
    BEGIN { RS = "\0"; bs = sprintf("%c", 92); for (i = 0; i < 256; i++) ord[sprintf("%c", i)] = i }
    {
      n = length($0)
      for (i = 1; i <= n; i++) {
        c = substr($0, i, 1); v = ord[c]
        if      (c == "\\") out = out bs bs
        else if (c == "\"") out = out bs "\""
        else if (c == "\b") out = out bs "b"
        else if (c == "\t") out = out bs "t"
        else if (c == "\n") out = out bs "n"
        else if (c == "\f") out = out bs "f"
        else if (c == "\r") out = out bs "r"
        else if (v < 32)    out = out bs "u" sprintf("%04x", v)
        else                out = out c
      }
    }
    END { printf "%s", out }
  '
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
  # O diretório pode ter sumido entre o source do _lib.sh e agora (limpeza
  # concorrente, --reset em paralelo). Recriar aqui é barato.
  mkdir -p "$RESULTS_DIR" 2>/dev/null || true
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

  # Result que não foi persistido NÃO pode ser reportado como aprovação.
  # Observado: o `cat >` falhou com "No such file or directory" e o check
  # seguiu imprimindo "✓ PASSED" e saindo 0 — falha de escrita virando sucesso,
  # e o orquestrador não teria result nenhum para agregar.
  if [ ! -s "$out" ]; then
    log_fail "$agent: NÃO consegui gravar o resultado em $out"
    log_fail "  O check rodou, mas o veredito não foi persistido — isto não é"
    log_fail "  'nenhum problema encontrado'. Tratando como erro."
    return 4
  fi

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
# ─── Piso de exclusão: uma definição, DOIS consumidores ───
# O wrapper do ripgrep e o fallback de grep varriam árvores diferentes: o
# fallback excluía `dist` e o ripgrep não; o ripgrep excluía `coverage` e
# minificados e o fallback não. O mesmo check via coisas diferentes conforme a
# máquina tivesse ripgrep — e a divergência só aparece onde ninguém testa.
#
# Derivar os dois formatos da MESMA lista torna a divergência impossível por
# construção, que é melhor que um teste conferindo se elas continuam iguais.
#
# Aqui entra só o que NUNCA é alvo legítimo de auditoria. `dist`, `build` e
# `.next` ficam de FORA de propósito: varrer o bundle construído é exatamente o
# certo para runtime-secrets e pii-encryption, que procuram segredo assado no
# artefato entregue ao cliente.
BLINDAR_IGNORE_DIRS="node_modules .git .blindar .blindar.* coverage"
BLINDAR_IGNORE_FILES="*.min.js *.min.css *.map"
export BLINDAR_IGNORE_DIRS BLINDAR_IGNORE_FILES

# ─── PATH da MÁQUINA vs PATH deste shell (Windows) ───
# No Windows o instalador grava o diretório no PATH persistente do usuário, mas
# processo já em execução não recebe a mudança — só o PRÓXIMO shell. Quem acaba
# de instalar gitleaks/trivy/ripgrep lê "Successfully installed", roda o blindar
# e vê os checks correspondentes saírem `skipped`, sem relação aparente.
#
# Aqui a diferença é resolvida na fonte: lê o PATH persistente do registro e
# junta o que este processo ainda não tem. Não inventa caminho nem mantém lista
# de gerenciador de pacote — usa o que a máquina já declarou.
#
# Uma vez por árvore de processos: o marcador é exportado e os 107 checks filhos
# pulam a leitura.
if [ -z "${BLINDAR_PATH_SYNCED:-}" ] && [ -n "${WINDIR:-${SystemRoot:-}}" ]; then
  export BLINDAR_PATH_SYNCED=1
  # MSYS2_ARG_CONV_EXCL obrigatório: sem ele o runtime MSYS reescreve o argumento
  # `/v` como se fosse caminho POSIX ("C:/Program Files/Git/v") e o reg responde
  # "sintaxe inválida". O erro vai pro /dev/null, a variável fica vazia e o sync
  # não acontece — sem nenhum sinal de que tentou.
  _persist="$(MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' \
    reg query 'HKCU\Environment' /v Path 2>/dev/null \
    | sed -n 's/.*REG_[A-Z_]*SZ[[:space:]]*//p' | tr -d '\r')"
  if [ -n "${_persist:-}" ]; then
    _IFS_OLD="$IFS"; IFS=';'
    for _p in $_persist; do
      [ -z "$_p" ] && continue
      case "$_p" in *'%'*) continue ;; esac   # %VAR% não expandido: não arriscar
      # cygpath converte C:\x → /c/x. Sem ele o bash trata como caminho inválido
      # e a entrada some silenciosamente — mesma classe de perda que este bloco
      # existe pra evitar.
      _u="$(cygpath -u "$_p" 2>/dev/null)" || _u=""
      [ -z "$_u" ] || [ ! -d "$_u" ] && continue
      case ":$PATH:" in *":$_u:"*) continue ;; esac
      PATH="$PATH:$_u"
    done
    IFS="$_IFS_OLD"; unset _IFS_OLD _p _u
    export PATH
  fi
  unset _persist
fi

# ─── Achar o ripgrep mesmo fora do PATH ───
# O gerenciador instala e diz "instalado com sucesso"; o PATH só muda no PRÓXIMO
# shell. Entre esses dois momentos o rg EXISTE na máquina e o blindar o declara
# ausente — e ausente aqui custa 60 dos 107 checks virando `skipped`, o que não
# é reprovação nem aprovação, é medição que não aconteceu.
#
# Quem acabou de instalar lê "instalado com sucesso" e roda: recebe um relatório
# com metade da cobertura e nenhum motivo aparente. É o modo de falha que este
# projeto inteiro existe para não ter: perda silenciosa de sinal.
#
# `type -P` de propósito, não `command -v`: o Claude Code define `rg` como FUNÇÃO
# de shell apontando para o ripgrep embutido nele. `command -v` acha a função e
# responde "tem rg" — mas função de shell não é herdada por processo filho, e os
# checks rodam como scripts filhos. Daria "tem" no agente e "não tem" no check.
blindar_probe_rg() {
  local c
  for c in \
    "${LOCALAPPDATA:-$HOME/AppData/Local}"/Microsoft/WinGet/Links/rg.exe \
    "${LOCALAPPDATA:-$HOME/AppData/Local}"/Microsoft/WinGet/Packages/BurntSushi.ripgrep*/*/rg.exe \
    "$HOME"/scoop/shims/rg.exe \
    /c/ProgramData/chocolatey/bin/rg.exe \
    "$HOME"/.cargo/bin/rg \
    /opt/homebrew/bin/rg /usr/local/bin/rg /usr/bin/rg /snap/bin/rg
  do
    [ -x "$c" ] && { printf '%s' "$c"; return 0; }
  done
  return 1
}

if [ -n "${BLINDAR_RG_BIN:-}" ] && [ ! -x "$BLINDAR_RG_BIN" ]; then
  unset BLINDAR_RG_BIN   # herdado de um ambiente onde valia; aqui não vale mais
fi
if [ -z "${BLINDAR_RG_BIN:-}" ]; then
  if type -P rg >/dev/null 2>&1; then
    BLINDAR_RG_BIN="$(type -P rg)"
  else
    # Achado fora do PATH conta como achado, mas o operador precisa SABER que o
    # PATH dele não tem — senão o mesmo comando falha noutro contexto e a causa
    # fica invisível. `doctor.sh` lê esta var e mostra o caminho.
    BLINDAR_RG_BIN="$(blindar_probe_rg || true)"
    [ -n "$BLINDAR_RG_BIN" ] && export BLINDAR_RG_OFF_PATH=1
  fi
fi

if [ -n "${BLINDAR_RG_BIN:-}" ]; then
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
  # ─── Piso de exclusão comum aos DOIS caminhos ───
  # O fallback de grep (abaixo) sempre excluiu node_modules/.git/dist/.blindar
  # no seu `base`. Este wrapper não excluía nada — então o mesmo check varria
  # árvores diferentes conforme o ripgrep estivesse instalado ou não, e o
  # desacordo só aparecia COM ripgrep, isto é, em produção e não no fallback.
  #
  # Consequência observada rodando contra projeto real: o content-quality
  # varreu `.blindar/results/*.json` (a própria saída do blindar) e reportou o
  # JSON de findings como "erro técnico vazando pra UI" — auto-detecção
  # reentrante. `.blindar.*` cobre os diretórios de arquivo de runs anteriores.
  #
  # Aqui entra só o que NUNCA é alvo legítimo de auditoria. `dist`, `build` e
  # `.next` ficam de FORA deste piso de propósito: varrer o bundle construído é
  # exatamente o certo para runtime-secrets e pii-encryption, que procuram
  # segredo assado no artefato do cliente.
  BLINDAR_RG_BASE_IGNORE=()
  for _d in $BLINDAR_IGNORE_DIRS;  do BLINDAR_RG_BASE_IGNORE+=(-g "!$_d"); done
  for _f in $BLINDAR_IGNORE_FILES; do BLINDAR_RG_BASE_IGNORE+=(-g "!**/$_f"); done
  unset _d _f
  export BLINDAR_RG_BASE_IGNORE
  rg() {
    MSYS2_ARG_CONV_EXCL='*' MSYS_NO_PATHCONV=1 \
      command "$BLINDAR_RG_BIN" --type-add 'prisma:*.prisma' --type-add 'env:.env*' \
      "${BLINDAR_RG_BASE_IGNORE[@]}" "$@" </dev/null
  }
  export -f rg
fi

if [ -z "${BLINDAR_RG_BIN:-}" ]; then
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
    local base=(-r)
    local _d _f
    for _d in $BLINDAR_IGNORE_DIRS;  do base+=(--exclude-dir="$_d"); done
    for _f in $BLINDAR_IGNORE_FILES; do base+=(--exclude="$_f"); done
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
