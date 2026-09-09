#!/usr/bin/env bash
# Materialização determinística do agente: mock-killer
# Detecta console.log, TODO sem issue, mock em produção, botões vazios.
# Respeita .blindar/intelligence.yml ignore_paths e markers // @blindar:keep

BLINDAR_AGENT="check-mock-killer"
source "$(dirname "$0")/_lib.sh"

log_section "Check: anti-mock + console.log + TODO órfão"

if ! command -v rg >/dev/null 2>&1; then
  log_fail "ripgrep (rg) requerido. Instale: brew install ripgrep"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

# Paths padrão a ignorar (sobrepostos via intelligence.yml se existir)
# Os globs PRECISAM ir com -g. Soltos, o ripgrep real os trata como CAMINHOS:
# todos inválidos → não sobra caminho válido → varre nada, sai 2, check passa
# sempre. O fallback de grep do _lib.sh aceita a forma solta por compat, então
# o bug só aparece COM ripgrep instalado.
IGNORE_GLOBS=(-g '!.next' -g '!.nuxt' -g '!out' -g '!.svelte-kit' 
  -g '!node_modules' -g '!vendor' -g '!dist' -g '!build' -g '!.next' -g '!coverage'
  -g '!.blindar' -g '!.git'
  -g '!**/*.gen.ts' -g '!**/*.generated.ts' -g '!**/*.test.*' -g '!**/*.spec.*'
  -g '!**/*.stories.*' -g '!**/__mocks__/**' -g '!**/fixtures/**'
  -g '!**/test/**' -g '!**/tests/**' -g '!**/__tests__/**'
  -g '!**/*.dev.ts' -g '!scripts/**'
)
load_intelligence_globs "$BLINDAR_AGENT"

# 1. console.log/debug/warn em código de produção
log_info "Buscando console.log em código de prod..."
TMP=$(mktemp)
rg -n "console\.(log|debug|warn|trace)\(" --type ts --type js --type py "${IGNORE_GLOBS[@]}" "${INTEL_GLOBS[@]}" > "$TMP" 2>/dev/null || true

# Filtra linhas com marker @blindar:keep
grep -v "@blindar:keep" "$TMP" > "$TMP.filtered" || true
mv "$TMP.filtered" "$TMP"

# ─── Debug esquecido × log estruturado ───
# Todo `console.*` saia como `high`, com a régua de frontend aplicada a
# backend. Medido no FastList (set/2026): 206 high, todos da observabilidade
# que o projeto construiu à mão — `[WA]`, `[cobranca]`, `[migrar]` — com o
# dado sensível já redigido antes de imprimir. Baseline arquitetural ocupando
# o contador de high esconde o high de verdade que estiver no meio.
#
# Em backend Node, stdout/stderr É o mecanismo de log: PM2, journald e o
# runtime do container capturam dali. O que sobra de defeito é o debug solto
# — `console.log("aqui")`, `console.log(obj)` — e esse continua `high`.
#
# A marca de log estruturado é o prefixo de módulo no primeiro argumento
# (`console.log("[cobranca] ...")`). Quem tem prefixo vira `low` com nome
# próprio; quem não tem segue bloqueando.
CONSOLE_COUNT=$(wc -l < "$TMP" || echo 0)
if [ "$CONSOLE_COUNT" -gt 0 ]; then
  CONSOLE_HIGH=0; CONSOLE_STRUCT=0
  while IFS=: read -r file line content; do
    [ -z "$file" ] && continue
    if printf '%s' "$content" | grep -qE 'console\.(log|debug|warn|trace)\([[:space:]]*(`|"|'"'"')\[[A-Za-z0-9_:.\-]+\]'; then
      CONSOLE_STRUCT=$((CONSOLE_STRUCT+1))
      add_finding "low" "log estruturado (prefixo de módulo) em stdout — válido em backend, revise se este arquivo roda no browser: $(trim_ws "$content")" "$file" "$line"
    else
      CONSOLE_HIGH=$((CONSOLE_HIGH+1))
      add_finding "high" "console em produção: $(trim_ws "$content")" "$file" "$line"
    fi
  done < "$TMP"
  [ "$CONSOLE_HIGH" -gt 0 ] && log_fail "$CONSOLE_HIGH console.* sem prefixo de módulo (debug esquecido)"
  [ "$CONSOLE_STRUCT" -gt 0 ] && log_warn "$CONSOLE_STRUCT console.* com prefixo de módulo — contado como low (observabilidade reconhecida)"
else
  log_pass "Zero console em código de produção"
fi
rm -f "$TMP"

# 2. TODOs sem issue link
log_info "Buscando TODO/FIXME sem issue link..."
TMP=$(mktemp)
rg -n "\b(TODO|FIXME|HACK|XXX)\b" "${IGNORE_GLOBS[@]}" "${INTEL_GLOBS[@]}" 2>/dev/null | \
  grep -vE "TODO\(issue-#[0-9]+\)|TODO\(@[a-z]+\)|@blindar:keep-todo" > "$TMP" || true

TODO_COUNT=$(wc -l < "$TMP" || echo 0)
if [ "$TODO_COUNT" -gt 0 ]; then
  while IFS=: read -r file line content; do
    [ -z "$file" ] && continue
    add_finding "med" "TODO sem issue: $(trim_ws "$content")" "$file" "$line"
  done < "$TMP"
  log_warn "$TODO_COUNT TODO/FIXME sem issue link (use TODO(issue-#123): ...)"
else
  log_pass "Todos os TODOs têm issue link ou owner"
fi
rm -f "$TMP"

# 3. Mock/fake/stub fora de pasta de teste
log_info "Buscando mocks em código de produção..."
TMP=$(mktemp)
rg -n "(mock|stub|fake|dummy)[A-Z]" --type ts --type py "${IGNORE_GLOBS[@]}" "${INTEL_GLOBS[@]}" 2>/dev/null > "$TMP" || true
grep -v "@blindar:keep" "$TMP" > "$TMP.filtered" || true
mv "$TMP.filtered" "$TMP"

MOCK_COUNT=$(wc -l < "$TMP" || echo 0)
if [ "$MOCK_COUNT" -gt 0 ]; then
  while IFS=: read -r file line content; do
    [ -z "$file" ] && continue
    add_finding "high" "mock em produção: $(trim_ws "$content")" "$file" "$line"
  done < "$TMP"
  log_fail "$MOCK_COUNT mocks em código de produção"
fi
rm -f "$TMP"

# 4. Botões com handler vazio
log_info "Buscando botões com onClick vazio..."
TMP=$(mktemp)
rg -n "onClick=\{\s*\(\s*\)\s*=>\s*\{\s*\}"   "${IGNORE_GLOBS[@]}" "${INTEL_GLOBS[@]}" > "$TMP" 2>/dev/null || true
EMPTY_CLICK=$(wc -l < "$TMP" || echo 0)
if [ "$EMPTY_CLICK" -gt 0 ]; then
  while IFS=: read -r file line content; do
    [ -z "$file" ] && continue
    add_finding "crit" "Botão sem handler real: $(trim_ws "$content")" "$file" "$line"
  done < "$TMP"
  log_fail "$EMPTY_CLICK botão(ões) com onClick vazio — BLOQUEIA release"
fi
rm -f "$TMP"

# 5. Status final
# Só `low` não reprova: mesma regra do emit_result, onde med/low são
# informativos. Antes, um único log estruturado reprovava o check inteiro — e
# reprovação que o operador aprende a ignorar deixa de ser reprovação.
TOTAL=${#FINDINGS[@]}
BLOCKING=0
for _f in "${FINDINGS[@]:-}"; do
  case "$_f" in
    *'"severity":"crit"'*|*'"severity":"high"'*|*'"severity":"med"'*) BLOCKING=$((BLOCKING+1)) ;;
  esac
done
if [ "$BLOCKING" -gt 0 ]; then
  emit_result "$BLINDAR_AGENT" "failed" 1
  exit 1
fi
if [ "$TOTAL" -gt 0 ]; then
  log_warn "$TOTAL achado(s) informativo(s) (low) — sai no relatório, não reprova"
fi

emit_result "$BLINDAR_AGENT" "passed" 0
exit 0
