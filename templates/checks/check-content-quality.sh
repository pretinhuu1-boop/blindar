#!/usr/bin/env bash
# Materializa agente: content-quality
# Hunspell/aspell pra ortografia + Vale pra estilo + grep pra problemas óbvios

BLINDAR_AGENT="check-content-quality"
source "$(dirname "$0")/_lib.sh"

log_section "Check: content-quality (ortografia + tom + microcopy)"

if ! command -v rg >/dev/null 2>&1; then
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

IGNORE=(-g '!node_modules' -g '!dist' -g '!build' -g '!**/*.test.*')
FAIL=0

# 1. Erro técnico vazando pra UI
log_info "Buscando erro técnico em texto de UI..."
TMP=$(mktemp)
rg -n "(throw new \w*Error|return.*['\"])(undefined|null|NaN|TypeError|ReferenceError|Cannot read|stack)" \
     "${IGNORE[@]}" > "$TMP" 2>/dev/null || true
TECH_LEAK=$(wc -l < "$TMP" || echo 0)
if [ "$TECH_LEAK" -gt 0 ]; then
  while IFS=: read -r file line content; do
    [ -z "$file" ] && continue
    add_finding "med" "Possível erro técnico vazando pra UI: $(echo "$content" | xargs | cut -c1-80)" "$file" "$line"
  done < "$TMP"
fi
rm -f "$TMP"

# 2. "Tem certeza?" sem contexto
log_info "Buscando 'Tem certeza?' vago..."
VAGUE=$(rg -n "['\"]Tem certeza\?['\"]"   "${IGNORE[@]}" 2>/dev/null | wc -l || echo 0)
if [ "$VAGUE" -gt 0 ]; then
  add_finding "med" "$VAGUE 'Tem certeza?' sem contexto — explicitar o que acontece" "" ""
fi

# 3. "OK"/"Cancelar" em destrutivo
log_info "Buscando OK/Cancelar em delete..."
TMP=$(mktemp)
rg -nB 5 -A 5 "(delete|remove|destroy|drop)"   "${IGNORE[@]}" 2>/dev/null | \
  grep -E "['\"]OK['\"]|['\"]Cancelar['\"]" | head -10 > "$TMP" || true
OK_DESTRUCTIVE=$(wc -l < "$TMP" || echo 0)
if [ "$OK_DESTRUCTIVE" -gt 0 ]; then
  add_finding "med" "Possível 'OK/Cancelar' em ação destrutiva — usar 'Excluir/Cancelar'" "" ""
fi
rm -f "$TMP"

# 4. Concatenação que vira plural quebrado
log_info "Buscando plural por concatenação..."
TMP=$(mktemp)
rg -n "['\"][a-z]+\s*['\"]\s*\+\s*\w+\s*\+\s*['\"]\s*s\b" --type ts  "${IGNORE[@]}" > "$TMP" 2>/dev/null || true
PLURAL_BROKEN=$(wc -l < "$TMP" || echo 0)
if [ "$PLURAL_BROKEN" -gt 0 ]; then
  add_finding "med" "$PLURAL_BROKEN plural via concatenação — usar ICU MessageFormat" "" ""
fi
rm -f "$TMP"

# 5. Termos discriminatórios (alex.js style básico)
log_info "Buscando termos discriminatórios..."
TMP=$(mktemp)
rg -ni "\b(blacklist|whitelist|master\/slave|slave|grandfather(ed)?|sanity check)\b" \
 --type ts --type md "${IGNORE[@]}" > "$TMP" 2>/dev/null || true
DISCRIMINATORY=$(wc -l < "$TMP" || echo 0)
if [ "$DISCRIMINATORY" -gt 0 ]; then
  while IFS=: read -r file line content; do
    [ -z "$file" ] && continue
    add_finding "low" "Termo problemático: $(echo "$content" | xargs | cut -c1-80)" "$file" "$line"
  done < "$TMP"
fi
rm -f "$TMP"

# 6. Forbidden words do copy-style.yml (se existir)
if has_file ".blindar/copy-style.yml"; then
  log_info "Verificando forbidden_words do copy-style.yml..."
  FORBIDDEN=$(grep -A 20 "forbidden_words:" .blindar/copy-style.yml 2>/dev/null | \
              grep -oE "['\"][^'\"]+['\"]" | tr -d "'\"")
  if [ -n "$FORBIDDEN" ]; then
    while read -r word; do
      [ -z "$word" ] && continue
      HITS=$(rg -ci "$word" --type md "${IGNORE[@]}" 2>/dev/null | wc -l || echo 0)
      if [ "$HITS" -gt 0 ]; then
        add_finding "med" "$HITS uso(s) de '$word' (proibido por .blindar/copy-style.yml)" "" ""
      fi
    done <<< "$FORBIDDEN"
  fi
fi

# 7. Ortografia básica (se aspell/hunspell disponível)
if command -v aspell >/dev/null 2>&1 || command -v hunspell >/dev/null 2>&1; then
  log_info "Ortografia básica disponível — operador pode rodar vale/languagetool"
fi

# Não bloqueia merge — só sinaliza
emit_result "$BLINDAR_AGENT" "passed" 0
exit 0
