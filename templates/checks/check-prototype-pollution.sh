#!/usr/bin/env bash
# Materializa: prototype-pollution (JS/TS — __proto__/constructor sink + merge inseguro)
# Fonte: docs/book-insights.md § Rossi/Crawley. Vuln clássica (CVE lodash/minimist).
BLINDAR_AGENT="check-prototype-pollution"
source "$(dirname "$0")/_lib.sh"
log_section "Check: prototype pollution (JS)"

if ! command -v rg >/dev/null 2>&1; then emit_result "$BLINDAR_AGENT" "skipped" 0; exit 0; fi

IGNORE=(-g '!node_modules' -g '!dist' -g '!build' -g '!.blindar' -g '!.git'
        -g '!**/*.test.*' -g '!**/*.spec.*')
load_intelligence_globs "$BLINDAR_AGENT"

# 1. Escrita direta em __proto__ / constructor.prototype com bracket/user key (sink)
#    Ex: obj[key] = val  onde key vem do usuário e não há guard; ou obj["__proto__"] = ...
TMP=$(mktemp)
rg -n "\[[\"']__proto__[\"']\]|\.__proto__\s*=|constructor\s*\[[\"']prototype[\"']\]|\.constructor\.prototype\s*=" \
  --type ts --type js "${IGNORE[@]}" "${INTEL_GLOBS[@]}" 2>/dev/null | \
  grep -vE "Object\.create\(null\)|@blindar:keep|hasOwnProperty" > "$TMP" || true
while IFS=: read -r file line content; do
  [ -z "$file" ] && continue
  add_finding "high" "Escrita em __proto__/constructor.prototype — prototype pollution: $(echo "$content" | xargs | cut -c1-70)" "$file" "$line"
done < "$TMP"
rm -f "$TMP"

# 2. Merge recursivo caseiro sem guard de chave perigosa
#    função *merge*/*extend*/deepMerge que atribui recursivamente e NÃO filtra
#    __proto__/constructor/prototype. Heurística: arquivo tem merge recursivo E
#    não menciona o guard.
TMP=$(mktemp)
rg -ln "function\s+\w*[mM]erge|const\s+\w*[mM]erge\s*=|deepMerge|deepExtend" \
  --type ts --type js "${IGNORE[@]}" "${INTEL_GLOBS[@]}" 2>/dev/null > "$TMP" || true
while IFS= read -r file; do
  [ -z "$file" ] && continue
  # Se o arquivo faz atribuição recursiva por chave dinâmica...
  if rg -q "target\[\w+\]\s*=|dest\[\w+\]\s*=|out\[\w+\]\s*=|acc\[\w+\]\s*=" "$file" 2>/dev/null; then
    # ...mas NÃO tem guard REAL → finding. Guard real = chave perigosa como
    # STRING LITERAL (comparação/skip), Object.create(null), ou hasOwnProperty.
    # (menção solta a "prototype" em comentário NÃO conta como guard.)
    if ! rg -q "[\"']__proto__[\"']|Object\.create\(null\)|hasOwnProperty\.call|[\"']constructor[\"']" "$file" 2>/dev/null; then
      LINE=$(rg -n "function\s+\w*[mM]erge|const\s+\w*[mM]erge\s*=|deepMerge|deepExtend" "$file" 2>/dev/null | head -1 | cut -d: -f1)
      add_finding "high" "Merge recursivo sem bloquear __proto__/constructor — prototype pollution" "$file" "${LINE:-}"
    fi
  fi
done < "$TMP"
rm -f "$TMP"

# 3. JSON.parse de input do usuário direto em merge/assign (reviver ausente)
#    Sinal fraco (med): Object.assign({}, JSON.parse(req...))
ASSIGN_PARSE=$(rg -n "Object\.assign\([^)]*JSON\.parse\([^)]*\b(req|request|body|query|params)\b" \
  --type ts --type js "${IGNORE[@]}" "${INTEL_GLOBS[@]}" 2>/dev/null | wc -l)
[ "$ASSIGN_PARSE" -gt 0 ] && add_finding "med" "$ASSIGN_PARSE Object.assign de JSON.parse(user input) — validar chaves" "" ""

# Decisão: qualquer high/crit reprova
CRITS=$(printf '%s\n' "${FINDINGS[@]:-}" | grep -c '"severity":"crit"' 2>/dev/null)
HIGHS=$(printf '%s\n' "${FINDINGS[@]:-}" | grep -c '"severity":"high"' 2>/dev/null)
if [ "$CRITS" -gt 0 ] || [ "$HIGHS" -gt 0 ]; then
  emit_result "$BLINDAR_AGENT" "failed" 1
  exit 1
fi
emit_result "$BLINDAR_AGENT" "passed" 0
