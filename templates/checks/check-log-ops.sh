#!/usr/bin/env bash
# Materialização do agente: log-ops-retention
# Ciclo de vida do log EM DISCO — rotação, um arquivo por processo, retenção
# com guardas, disco cheio, permissões, volume.
#
# NÃO audita conteúdo de log (formato/correlação → check-observability.sh) nem
# política de redação (→ check-runtime-secrets.sh). Ver agents/log-ops-retention.md.

BLINDAR_AGENT="check-log-ops"
source "$(dirname "$0")/_lib.sh"

log_section "Check: ciclo de vida do log em disco"

# NOTA: os globs vão com -g. Passar '!glob' solto faz o ripgrep real tratá-lo
# como CAMINHO, varrer nada e o check passar sempre (bug histórico do IGNORE).
IGNORE=(-g '!node_modules' -g '!dist' -g '!build' -g '!.next' -g '!**/*.test.*'
        -g '!**/*.spec.*' -g '!**/__mocks__/**' -g '!logs/**')
load_intelligence_globs "$BLINDAR_AGENT"

# ── Escreve log em arquivo? Se não, o resto não se aplica ───────────────────
# stdout puro é legítimo QUANDO há coletor externo (ver observability.md).
WRITES_FILE=0
rg -q "appendFileSync\s*\(|createWriteStream\s*\(.*\.log|RotatingFileHandler|TimedRotatingFileHandler|logging\.FileHandler|winston\.transports\.File|pino\.destination|lumberjack|log\.New\(.*os\.OpenFile" \
  --type ts --type js --type py --type go "${IGNORE[@]}" "${INTEL_GLOBS[@]}" && WRITES_FILE=1

if [ "$WRITES_FILE" -eq 0 ]; then
  log_pass "projeto não escreve log em arquivo — ciclo em disco não se aplica"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi
log_info "projeto escreve log em arquivo — auditando ciclo de vida"

# ── 1. Código que apaga diretório SEM guarda de path/symlink ───────────────
# A guarda mínima: regex de data no basename, realpath dentro do LOG_DIR, e
# lstat pra não seguir symlink. Sem isso, um nome inesperado apaga o que não devia.
log_info "Buscando exclusão de diretório sem guarda..."
TMP=$(mktemp)
rg -n "rmSync\s*\([^)]*recursive\s*:\s*true|shutil\.rmtree\s*\(|os\.RemoveAll\s*\(|rm\s+-rf" \
  --type ts --type js --type py --type go --type sh "${IGNORE[@]}" "${INTEL_GLOBS[@]}" 2>/dev/null \
  | grep -v "@blindar:keep" > "$TMP" || true

while IFS=: read -r file line content; do
  [ -z "$file" ] && continue
  # Guardas aceitas no MESMO arquivo: regex de data, realpath e lstat/symlink.
  HAS_DATE_RE=0; HAS_REALPATH=0; HAS_SYMLINK=0
  grep -qE '\\d\{4\}|\[0-9\]\{4\}|%Y-%m-%d' "$file" 2>/dev/null && HAS_DATE_RE=1
  grep -qE 'realpath|resolve\(|os\.path\.realpath|filepath\.EvalSymlinks' "$file" 2>/dev/null && HAS_REALPATH=1
  grep -qE 'lstat|is_symlink|islink|isSymbolicLink' "$file" 2>/dev/null && HAS_SYMLINK=1
  MISSING=$((3 - HAS_DATE_RE - HAS_REALPATH - HAS_SYMLINK))
  if [ "$MISSING" -gt 0 ]; then
    add_finding "crit" "Exclusão recursiva sem guarda completa (falta: $(
      [ "$HAS_DATE_RE" -eq 0 ] && printf 'regex-de-data '
      [ "$HAS_REALPATH" -eq 0 ] && printf 'realpath '
      [ "$HAS_SYMLINK" -eq 0 ] && printf 'lstat-symlink '
    ))" "$file" "$line"
  fi
done < "$TMP"
rm -f "$TMP"

# ── 2. Rotação por tamanho ─────────────────────────────────────────────────
log_info "Verificando rotação..."
if ! rg -q "maxBytes|maxsize|max_bytes|maxSize|RotatingFileHandler|rotate|logrotate" \
     --type ts --type js --type py --type go --type yaml "${IGNORE[@]}" "${INTEL_GLOBS[@]}"; then
  add_finding "med" "Log em arquivo sem rotação — arquivo cresce até encher o disco" "" ""
  log_warn "sem rotação configurada"
fi

# ── 3. Retenção ────────────────────────────────────────────────────────────
log_info "Verificando retenção..."
if ! rg -q "RETENTION|retention|retencao|sweep|prune|cleanup.*log|log.*cleanup" \
     --type ts --type js --type py --type go --type yaml "${IGNORE[@]}" "${INTEL_GLOBS[@]}"; then
  add_finding "high" "Sem retenção de log — disco enche e derruba a aplicação" "" ""
  log_fail "sem retenção"
fi

# ── 4. Escrita bloqueante no caminho quente ────────────────────────────────
log_info "Verificando escrita não-bloqueante..."
TMP=$(mktemp)
rg -n "appendFileSync|writeFileSync" --type ts --type js "${IGNORE[@]}" "${INTEL_GLOBS[@]}" 2>/dev/null \
  | grep -viE "flush|queue|batch|drain|@blindar:keep" > "$TMP" || true
BLOCKING=$(wc -l < "$TMP" | xargs)
if [ "${BLOCKING:-0}" -gt 0 ]; then
  while IFS=: read -r file line _; do
    [ -z "$file" ] && continue
    add_finding "med" "Escrita síncrona de log fora de flush/queue — bloqueia o caminho quente" "$file" "$line"
  done < "$TMP"
  log_warn "$BLOCKING escrita(s) síncrona(s) fora de flush"
fi
rm -f "$TMP"

# ── 5. Diretório de log versionado / dentro da imagem ──────────────────────
log_info "Verificando .gitignore / .dockerignore..."
if has_file ".gitignore" && ! grep -qE '^\s*/?(logs?|var/log)/?' .gitignore 2>/dev/null; then
  add_finding "med" "Diretório de log não está no .gitignore" ".gitignore" ""
  log_warn "log fora do .gitignore"
fi
if has_file "Dockerfile" && has_file ".dockerignore" && ! grep -qE '^\s*/?(logs?|var/log)/?' .dockerignore 2>/dev/null; then
  add_finding "med" "Diretório de log não está no .dockerignore — vai pra dentro da imagem" ".dockerignore" ""
fi

# ── 6. Container sem volume persistente pro log ────────────────────────────
if has_file "Dockerfile"; then
  log_info "Verificando volume persistente..."
  HAS_VOL=0
  grep -qiE '^\s*VOLUME' Dockerfile 2>/dev/null && HAS_VOL=1
  for f in docker-compose.yml docker-compose.yaml; do
    [ -f "$f" ] && grep -qE '^\s*volumes:' "$f" 2>/dev/null && HAS_VOL=1
  done
  if [ "$HAS_VOL" -eq 0 ]; then
    add_finding "high" "Container sem volume persistente — retenção vira 'até o próximo deploy'" "Dockerfile" ""
    log_fail "sem volume persistente pro log"
  fi
fi

# ── 7. Guarda de disco cheio ───────────────────────────────────────────────
if ! rg -q "statfs|disk_usage|diskFree|freeBytes|df -|bavail|bfree" \
     --type ts --type js --type py --type go "${IGNORE[@]}" "${INTEL_GLOBS[@]}"; then
  add_finding "med" "Sem guarda de disco cheio — log pode derrubar a aplicação" "" ""
fi

# ── Veredito ───────────────────────────────────────────────────────────────
TOTAL=${#FINDINGS[@]}
if [ "$TOTAL" -gt 0 ]; then
  CRITS=$(printf '%s\n' "${FINDINGS[@]}" | grep -c '"severity":"crit"')
  HIGHS=$(printf '%s\n' "${FINDINGS[@]}" | grep -c '"severity":"high"')
  if [ "$CRITS" -gt 0 ] || [ "$HIGHS" -gt 0 ]; then
    emit_result "$BLINDAR_AGENT" "failed" 1
    exit 1
  fi
fi

log_pass "ciclo de vida do log em disco OK"
emit_result "$BLINDAR_AGENT" "passed" 0
exit 0
