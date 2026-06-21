#!/usr/bin/env bash
# Materialização do agente: semgrep
# SAST profundo via Semgrep CLI. Mapeia output JSON do semgrep ao formato
# blindar (add_finding com severity crit/high/med/low).
#
# Env vars:
#   BLINDAR_SEMGREP_CONFIG   — config do semgrep (default: auto)
#                              ex: auto | p/security-audit | p/owasp-top-ten
#   BLINDAR_SEMGREP_TIMEOUT  — timeout em segundos (default: 120)
#   BLINDAR_CHANGED_FILES    — se set, roda só nesses arquivos
#                              (espaço-separado ou newline-separado)
#
# Flags:
#   --only-changed-files     — usa BLINDAR_CHANGED_FILES como target paths

BLINDAR_AGENT="check-semgrep"
source "$(dirname "$0")/_lib.sh"

log_section "Check: semgrep (SAST)"

# 1. Detecção: semgrep instalado?
if ! command -v semgrep >/dev/null 2>&1; then
  log_warn "Semgrep não instalado — instale via 'pipx install semgrep' ou 'brew install semgrep'"
  add_finding "low" "Semgrep não instalado — instale via 'pipx install semgrep' ou 'brew install semgrep'" "" ""
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

# 2. Config / timeout
SEMGREP_CONFIG="${BLINDAR_SEMGREP_CONFIG:-auto}"
SEMGREP_TIMEOUT="${BLINDAR_SEMGREP_TIMEOUT:-120}"

# 3. --only-changed-files
ONLY_CHANGED=0
for arg in "$@"; do
  case "$arg" in
    --only-changed-files) ONLY_CHANGED=1 ;;
  esac
done

TARGETS=(".")
if [ "$ONLY_CHANGED" -eq 1 ] && [ -n "${BLINDAR_CHANGED_FILES:-}" ]; then
  # quebra por espaço/newline
  # shellcheck disable=SC2206
  TARGETS=($BLINDAR_CHANGED_FILES)
  if [ "${#TARGETS[@]}" -eq 0 ]; then
    log_info "BLINDAR_CHANGED_FILES vazio — nada pra escanear"
    emit_result "$BLINDAR_AGENT" "passed" 0
    exit 0
  fi
  log_info "Modo --only-changed-files: ${#TARGETS[@]} arquivo(s)"
fi

log_info "Config: $SEMGREP_CONFIG | timeout: ${SEMGREP_TIMEOUT}s"

# 4. Roda semgrep
TMP=$(mktemp 2>/dev/null || mktemp -t semgrep)
ERR=$(mktemp 2>/dev/null || mktemp -t semgrep-err)

# Suporta config único ou multi (split em --config flags repetidas)
SEMGREP_CFG_ARGS=()
for cfg in $SEMGREP_CONFIG; do
  SEMGREP_CFG_ARGS+=("--config=$cfg")
done

# Nota: NÃO usar --quiet aqui. Em algumas versões/plataformas (semgrep
# 1.167 no Windows/Git Bash), --quiet faz exit code virar 2 mesmo em sucesso.
# stderr é redirecionado pro $ERR de qualquer jeito.
SEMGREP_CMD=(semgrep "${SEMGREP_CFG_ARGS[@]}" --json --no-git-ignore --disable-version-check "${TARGETS[@]}")

# Detecta plataforma — em Git Bash / MSYS / Cygwin, `timeout` (GNU) wrapando
# binário Python nativo (semgrep) trunca stdout pra "<ERROR: missing output>".
# Nesses casos, pulamos o `timeout` e confiamos no proprio --timeout do semgrep.
IS_WINDOWS=0
case "${OSTYPE:-}" in
  msys*|cygwin*|win32*) IS_WINDOWS=1 ;;
esac
[ -n "${MSYSTEM:-}" ] && IS_WINDOWS=1

if [ "$IS_WINDOWS" -eq 0 ] && command -v timeout >/dev/null 2>&1; then
  timeout "${SEMGREP_TIMEOUT}s" "${SEMGREP_CMD[@]}" > "$TMP" 2> "$ERR"
  SG_RC=$?
elif [ "$IS_WINDOWS" -eq 0 ] && command -v gtimeout >/dev/null 2>&1; then
  gtimeout "${SEMGREP_TIMEOUT}s" "${SEMGREP_CMD[@]}" > "$TMP" 2> "$ERR"
  SG_RC=$?
else
  # Sem wrapper de timeout (Windows ou ausência de coreutils).
  # Não passa --timeout do semgrep porque em algumas versões/plataformas
  # ele instabiliza o RPC subprocess. Semgrep já tem timeout default por arquivo.
  "${SEMGREP_CMD[@]}" > "$TMP" 2> "$ERR"
  SG_RC=$?
fi

# Semgrep exit codes:
#   0 = sucesso, nada encontrado
#   1 = findings encontrados (ou erro de parse) — depende de --error
#   2 = erro fatal (config inválida etc)
#   124 = timeout (do GNU timeout)
if [ "$SG_RC" -eq 124 ]; then
  log_warn "Semgrep timeout após ${SEMGREP_TIMEOUT}s"
  add_finding "med" "Semgrep timeout após ${SEMGREP_TIMEOUT}s — aumente BLINDAR_SEMGREP_TIMEOUT" "" ""
  rm -f "$TMP" "$ERR"
  emit_result "$BLINDAR_AGENT" "failed" 1
  exit 1
fi

if [ ! -s "$TMP" ]; then
  log_fail "Semgrep não produziu output"
  [ -s "$ERR" ] && log_fail "stderr: $(head -c 500 "$ERR")"
  add_finding "med" "Semgrep não produziu output (rc=$SG_RC). Veja stderr." "" ""
  rm -f "$TMP" "$ERR"
  emit_result "$BLINDAR_AGENT" "failed" 1
  exit 1
fi

# rc=2 = erro fatal do semgrep (config inválida, parse error etc).
# Mas pode coexistir com JSON válido contendo erros — sinaliza e segue.
if [ "$SG_RC" -ge 2 ] && [ "$SG_RC" -ne 124 ]; then
  log_warn "Semgrep retornou rc=$SG_RC (possível erro fatal). Veja .blindar/results/."
  [ -s "$ERR" ] && log_warn "stderr: $(head -c 300 "$ERR")"
  add_finding "med" "Semgrep retornou rc=$SG_RC — possível erro de config ou parse" "" ""
fi

# 5. Parse JSON — preferir node, fallback jq
PARSED=""
if command -v node >/dev/null 2>&1; then
  PARSED=$(node -e '
    const fs = require("fs");
    const data = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    const results = data.results || [];
    for (const r of results) {
      const sev = (r.extra && r.extra.severity) || "INFO";
      const msg = ((r.extra && r.extra.message) || r.check_id || "").replace(/\n/g, " ").replace(/\t/g, " ").trim();
      const path = r.path || "";
      const line = (r.start && r.start.line) || "";
      const id = r.check_id || "unknown";
      // tab-separated: sev \t id \t msg \t path \t line
      process.stdout.write(sev + "\t" + id + "\t" + msg + "\t" + path + "\t" + line + "\n");
    }
  ' "$TMP" 2>/dev/null)
elif command -v jq >/dev/null 2>&1; then
  PARSED=$(jq -r '
    .results[]? |
    [(.extra.severity // "INFO"),
     (.check_id // "unknown"),
     ((.extra.message // .check_id // "") | gsub("[\n\t]"; " ")),
     (.path // ""),
     (.start.line // "")] |
    @tsv
  ' "$TMP" 2>/dev/null)
else
  log_fail "Nem node nem jq disponíveis pra parse do output do semgrep"
  add_finding "high" "Parse de output do semgrep requer node ou jq" "" ""
  rm -f "$TMP" "$ERR"
  emit_result "$BLINDAR_AGENT" "failed" 1
  exit 1
fi

# 6. Itera findings e mapeia severity
TOTAL=0
CRITS=0
HIGHS=0
MEDS=0
LOWS=0

if [ -n "$PARSED" ]; then
  while IFS=$'\t' read -r sg_sev check_id msg path line; do
    [ -z "$sg_sev" ] && continue
    case "$sg_sev" in
      ERROR)   blindar_sev="crit"; CRITS=$((CRITS+1)) ;;
      WARNING) blindar_sev="high"; HIGHS=$((HIGHS+1)) ;;
      INFO)    blindar_sev="low";  LOWS=$((LOWS+1)) ;;
      *)       blindar_sev="med";  MEDS=$((MEDS+1)) ;;
    esac
    add_finding "$blindar_sev" "[semgrep:$check_id] $msg" "$path" "$line"
    TOTAL=$((TOTAL+1))
  done <<< "$PARSED"
fi

rm -f "$TMP" "$ERR"

log_info "Findings: $TOTAL (crit=$CRITS, high=$HIGHS, med=$MEDS, low=$LOWS)"

# 7. Decisão final
if [ "$TOTAL" -eq 0 ]; then
  emit_result "$BLINDAR_AGENT" "passed" 0
  exit 0
fi

if [ "$CRITS" -gt 0 ] || [ "$HIGHS" -gt 0 ]; then
  emit_result "$BLINDAR_AGENT" "failed" 1
  exit 1
fi

# Só MED/LOW = passed (informacional)
emit_result "$BLINDAR_AGENT" "passed" 0
exit 0
