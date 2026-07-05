#!/usr/bin/env bash
# Materializa agente: frontend-performance
# Bundle size, dynamic imports, image optimization, RSC default

BLINDAR_AGENT="check-frontend-performance"
source "$(dirname "$0")/_lib.sh"

log_section "Check: frontend-performance (bundle + LCP + RSC)"

if ! command -v rg >/dev/null 2>&1; then
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

HAS_UI=0
if has_dir "app" || has_dir "pages" || has_dir "src/components"; then
  HAS_UI=1
fi
if [ "$HAS_UI" -eq 0 ]; then
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

IGNORE=(-g '!node_modules' -g '!dist' -g '!build' -g '!.next' -g '!**/*.test.*')
load_intelligence_globs "$BLINDAR_AGENT"
FAIL=0

# 1. size-limit configurado
log_info "Verificando size-limit..."
if grep -qE "\"size-limit\":|\"@size-limit\":" package.json 2>/dev/null; then
  log_pass "size-limit detectado"
else
  add_finding "med" "Sem size-limit configurado — bundle pode crescer sem alerta (meta ≤400KB gzipped)" "package.json" ""
fi

# 2. next/image em vez de <img>
if is_nextjs; then
  log_info "Verificando next/image..."
  RAW_IMG=$(rg -c "<img "   "${IGNORE[@]}" "${INTEL_GLOBS[@]}" 2>/dev/null | wc -l || echo 0)
  if [ "$RAW_IMG" -gt 3 ]; then
    add_finding "high" "$RAW_IMG <img> sem next/image — perde optimization (AVIF/WebP/lazy)" "" ""
    log_warn "$RAW_IMG <img> raw em Next.js"
  fi
fi

# 3. 'use client' desnecessário (Next.js App Router)
if is_nextjs && has_dir "app"; then
  log_info "Buscando 'use client' desnecessário..."
  TMP=$(mktemp)
  for f in $(rg -l "^'use client'"   app/ 2>/dev/null); do
    if ! grep -qE "useState|useEffect|useRef|useReducer|onClick|onChange|onSubmit" "$f" 2>/dev/null; then
      echo "$f" >> "$TMP"
    fi
  done
  USELESS_USE_CLIENT=$(wc -l < "$TMP" 2>/dev/null || echo 0)
  if [ "$USELESS_USE_CLIENT" -gt 0 ]; then
    while read -r f; do
      [ -z "$f" ] && continue
      add_finding "med" "'use client' desnecessário (sem hooks/handlers)" "$f" ""
    done < "$TMP"
    log_warn "$USELESS_USE_CLIENT 'use client' desnecessário"
  fi
  rm -f "$TMP"
fi

# 4. React Compiler ativo (v19+)
if is_nextjs; then
  if grep -qE "reactCompiler.*true|@babel/preset-react.*compiler" next.config.* 2>/dev/null; then
    log_pass "React Compiler v1 ativo"
  else
    add_finding "low" "React Compiler v1 não ativo — useMemo/useCallback manuais provavelmente desnecessários" "next.config.*" ""
  fi
fi

# 5. Dynamic imports / code splitting
log_info "Verificando code splitting..."
DYNAMIC=$(rg -c "(dynamic\(|lazy\(|import\()" --type ts "${IGNORE[@]}" "${INTEL_GLOBS[@]}" 2>/dev/null | wc -l || echo 0)
if [ "$DYNAMIC" -eq 0 ] && [ "$HAS_UI" -eq 1 ]; then
  add_finding "low" "Sem dynamic import / React.lazy — tudo carrega no bundle inicial" "" ""
fi

# 6. Lighthouse CI
if ! [ -f ".lighthouserc.json" ] && ! [ -f "lighthouserc.json" ]; then
  add_finding "med" "Sem .lighthouserc.json — CWV (LCP/INP/CLS) não monitorados em CI" "" ""
fi

# 7. Pacotes pesados desnecessários (moment.js, lodash full, etc.)
log_info "Verificando pacotes pesados..."
HEAVY=()
for pkg in moment "lodash" jquery; do
  if grep -qE "\"$pkg\":" package.json 2>/dev/null; then
    HEAVY+=("$pkg")
  fi
done
if [ "${#HEAVY[@]}" -gt 0 ]; then
  for h in "${HEAVY[@]}"; do
    case "$h" in
      moment) add_finding "med" "moment.js detectado (deprecated) — usar date-fns ou Temporal API" "package.json" "" ;;
      lodash) add_finding "low" "lodash full — preferir lodash-es ou imports específicos" "package.json" "" ;;
      jquery) add_finding "med" "jQuery em projeto moderno — remover/migrar" "package.json" "" ;;
    esac
  done
fi

CRITS=$(printf '%s\n' "${FINDINGS[@]}" | grep -c '"severity":"crit"')
HIGHS=$(printf '%s\n' "${FINDINGS[@]}" | grep -c '"severity":"high"')
if [ "$CRITS" -gt 0 ] || [ "$HIGHS" -gt 0 ]; then
  emit_result "$BLINDAR_AGENT" "failed" 1
  exit 1
fi

emit_result "$BLINDAR_AGENT" "passed" 0
exit 0
