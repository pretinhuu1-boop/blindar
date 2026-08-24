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
  BLINDAR_MISSING_TOOL="semgrep"   # sem isto o result sai missing_tool:null
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

# ─── `--config=auto` quebra no Windows ───
# O `auto` faz o semgrep negociar o conjunto de regras com o registro remoto e
# validá-lo no `semgrep-core`. Nessa plataforma isso morre com
# "RPC subprocess exited with code 1 / semgrep-core rule validation failed",
# rc=2 — e o `--version` continua respondendo normalmente, então nem
# `command -v` nem a versão denunciam.
#
# Ruleset explícito funciona: medido, 68 regras rodaram e acharam a concatenação
# em query no mesmo arquivo em que o `auto` falhou.
#
# Cair para regra explícita é melhor que reprovar o SAST inteiro por causa da
# plataforma. E se a segunda tentativa também falhar, o bloco abaixo trata como
# não-verificado — nunca como "nada encontrado".
if [ "$SG_RC" -ge 2 ] && [ "$SG_RC" -ne 124 ] && [ "$SEMGREP_CONFIG" = "auto" ]; then
  log_warn "config 'auto' falhou (rc=$SG_RC) — tentando rulesets explícitos"
  [ -s "$ERR" ] && log_info "motivo: $(head -c 160 "$ERR" | tr '\n' ' ')"
  SEMGREP_CMD=(semgrep --config=p/security-audit --config=p/secrets
               --json --no-git-ignore --disable-version-check "${TARGETS[@]}")
  "${SEMGREP_CMD[@]}" > "$TMP" 2> "$ERR"
  SG_RC=$?
  [ "$SG_RC" -lt 2 ] && log_info "rulesets explícitos rodaram — SAST coberto"
fi

# ─── Última tentativa: o semgrep oficial, dentro de um container ───
# Quando nem `auto` nem ruleset explícito rodam, o problema é o binário desta
# plataforma, não a configuração. A imagem oficial é Linux, onde o semgrep
# funciona — e o wrapper quebrado do Windows sai inteiro do caminho.
#
# Medido nesta máquina: nativo rc=2 em qualquer scan; via container, 1074 regras
# e os dois achados esperados (eval com input do usuário e concatenação em query)
# no mesmo arquivo.
#
# Por que só agora, e não primeiro: container custa ~30s e um mount. Onde o
# nativo funciona — Linux, macOS — ele é mais rápido e não exige Docker. O
# fallback existe para a plataforma onde o caminho normal está quebrado, e não
# para substituí-lo.
#
# Desligar: BLINDAR_SEMGREP_NO_DOCKER=1
if [ "$SG_RC" -ge 2 ] && [ "$SG_RC" -ne 124 ] \
   && [ "${BLINDAR_SEMGREP_NO_DOCKER:-0}" != "1" ] \
   && command -v docker >/dev/null 2>&1; then
  if docker info >/dev/null 2>&1; then
    log_warn "semgrep nativo falhou (rc=$SG_RC) — tentando pela imagem oficial em container"
    # cygpath -m: o Docker no Windows precisa de C:/... e o bash entrega /c/...
    # Montar o caminho POSIX cria um bind vazio, e o scan varre nada e sai 0 —
    # que seria pior que falhar, porque "nada encontrado" pareceria resultado.
    _MNT="$PWD"
    command -v cygpath >/dev/null 2>&1 && _MNT="$(cygpath -m "$PWD")"
    MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' \
      docker run --rm -v "${_MNT}:/src" semgrep/semgrep \
        semgrep --config="$SEMGREP_CONFIG" --json --no-git-ignore \
        --disable-version-check /src > "$TMP" 2> "$ERR"
    SG_RC=$?
    # O container vê o projeto em /src; o relatório precisa apontar para o
    # caminho que existe na máquina de quem lê, senão o achado é inacionável.
    if [ "$SG_RC" -lt 2 ] && [ -s "$TMP" ] && command -v node >/dev/null 2>&1; then
      node -e '
        const fs = require("fs");
        try {
          const j = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
          for (const r of j.results || []) {
            if (typeof r.path === "string") r.path = r.path.replace(/^\/src\/?/, "");
          }
          fs.writeFileSync(process.argv[1], JSON.stringify(j));
        } catch (e) { /* deixa como veio: parse ruim é problema do bloco abaixo */ }
      ' "$TMP" 2>/dev/null
      log_info "semgrep rodou em container — SAST coberto"
    fi
  else
    log_info "docker instalado mas o daemon não responde — sem fallback de container"
  fi
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

# rc=2 = erro fatal do semgrep (config inválida, parse error, dependência do
# wrapper faltando).
#
# Isto emitia `med` e SEGUIA. Como o relatório vinha vazio, o check terminava em
# `passed` — o SAST inteiro não rodou e o status disse aprovado, com o motivo
# rebaixado a "possível erro" no meio de uma lista de achados menores.
#
# Medido no Windows: o `semgrep.exe` é um wrapper que chama `pysemgrep` pelo
# nome. Se o diretório de scripts do Python não está no PATH, o wrapper responde
# `--version` normalmente e falha em qualquer scan de verdade — então nem o
# `command -v` nem a versão denunciam. Só o rc do scan denuncia, e era ele que
# estava sendo engolido.
#
# Erro do scanner é ausência de medição, não ausência de achado. Vira `skipped`
# com `missing_tool`, que é o estado que diz "ninguém olhou".
if [ "$SG_RC" -ge 2 ] && [ "$SG_RC" -ne 124 ]; then
  log_fail "Semgrep terminou com erro (rc=$SG_RC) — o SAST não completou"
  [ -s "$ERR" ] && log_warn "stderr: $(head -c 300 "$ERR")"
  log_warn "isto NÃO é 'nenhuma vulnerabilidade': é análise que não aconteceu."
  # ─── Diagnóstico Windows: a causa mais comum NÃO é PATH ───
  # Medido nesta base: o `semgrep.exe` é achado e o `semgrep-core.exe` roda
  # isolado — o PATH está OK. O que quebra é o RPC pysemgrep → semgrep-core
  # quando o semgrep foi instalado sob o Python da Microsoft Store (o pacote
  # PythonSoftwareFoundation.Python.*), cujo AppContainer estrangula o spawn do
  # subprocesso: stderr traz "RPC subprocess exited" / "semgrep-core ... failed".
  # Apontar só "PATH" mandava o operador consertar o que não estava quebrado.
  SG_PATH="$(command -v semgrep 2>/dev/null || true)"
  if grep -qiE 'RPC subprocess|semgrep-core' "$ERR" 2>/dev/null \
     || printf '%s' "$SG_PATH" | grep -qi 'PythonSoftwareFoundation.Python'; then
    log_warn "causa provável: semgrep sob o Python da Microsoft Store (sandbox bloqueia o RPC do core)."
    log_warn "  destrave por um destes caminhos (em ordem de esforço):"
    log_warn "  1) suba o Docker Desktop e re-rode — este check cai no container oficial (SAST completo)."
    log_warn "  2) reinstale fora da Store:  winget install Python.Python.3.12  &&  py -3.12 -m pip install --user semgrep"
  else
    log_warn "no Windows, confira também se o diretório Scripts do Python está no PATH (o semgrep.exe chama pysemgrep pelo nome)."
  fi
  BLINDAR_MISSING_TOOL="semgrep(rc=$SG_RC)"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
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
