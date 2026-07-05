#!/usr/bin/env bash
# Materializa agente: network-security
# Verifica headers HTTP de segurança, rate limit, CORS allowlist

BLINDAR_AGENT="check-network-security"
source "$(dirname "$0")/_lib.sh"

log_section "Check: network-security (headers HTTP + rate limit + CORS)"

if ! command -v rg >/dev/null 2>&1; then
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

IGNORE=(-g '!node_modules' -g '!dist' -g '!build' -g '!**/*.test.*')
load_intelligence_globs "$BLINDAR_AGENT"

# 1. Headers HTTP de segurança obrigatórios
log_info "Verificando headers de segurança em código..."
REQUIRED_HEADERS=(
  "Strict-Transport-Security"
  "X-Content-Type-Options"
  "X-Frame-Options"
  "Referrer-Policy"
  "Content-Security-Policy"
)

# Heurística: procura em arquivos típicos de config (next.config, middleware.ts, helmet, etc)
SEARCH_FILES=$(find . -name "next.config.*" -o -name "middleware.ts" -o -name "*.middleware.ts" -o -name "server.ts" -o -name "app.ts" 2>/dev/null | grep -v node_modules | head -10)

MISSING_HEADERS=()
for header in "${REQUIRED_HEADERS[@]}"; do
  if ! rg -q "$header" $SEARCH_FILES 2>/dev/null; then
    # Verifica se usa Helmet (cobre vários)
    if ! rg -q "helmet|@helmetjs" --type ts --type js "${IGNORE[@]}" "${INTEL_GLOBS[@]}" 2>/dev/null; then
      MISSING_HEADERS+=("$header")
    fi
  fi
done

if [ "${#MISSING_HEADERS[@]}" -gt 0 ]; then
  for h in "${MISSING_HEADERS[@]}"; do
    add_finding "high" "Header $h não detectado (use Helmet ou middleware custom)" "" ""
  done
  log_warn "${#MISSING_HEADERS[@]} headers de segurança não detectados"
fi

# 2. CORS com origin: '*' E credentials: true (browser bloqueia, mas vaza intencao)
log_info "Buscando CORS errado..."
TMP=$(mktemp)
rg -n "origin\s*:\s*['\"]?\*['\"]?" --type ts --type js "${IGNORE[@]}" "${INTEL_GLOBS[@]}" -A 3 2>/dev/null > "$TMP" || true
if grep -q "credentials.*true" "$TMP"; then
  add_finding "high" "CORS origin '*' com credentials true (configuração perigosa)" "" ""
  log_fail "CORS mal configurado"
fi
rm -f "$TMP"

# 3. Rate limit em endpoints sensíveis
log_info "Verificando rate limit em /auth/*..."
HAS_RATELIMIT=$(rg -l "(rateLimit|@Throttle|express-rate-limit|@upstash/ratelimit|@fastify/rate-limit)" --type ts --type js "${IGNORE[@]}" "${INTEL_GLOBS[@]}" 2>/dev/null | head -1)
if [ -z "$HAS_RATELIMIT" ]; then
  add_finding "high" "Rate limit não detectado — endpoints /auth/* vulneráveis a brute force" "" ""
  log_fail "Sem rate limit detectado"
fi

# 4. HSTS preload em produção
HSTS_PRELOAD=$(rg -l "Strict-Transport-Security.*preload" "${IGNORE[@]}" "${INTEL_GLOBS[@]}" 2>/dev/null | head -1)
if [ -n "$HSTS_PRELOAD" ]; then
  log_pass "HSTS com preload detectado"
fi

# 5. CSP com 'unsafe-inline' ou 'unsafe-eval' (CRIT)
log_info "Buscando CSP unsafe-*..."
TMP=$(mktemp)
rg -n "'unsafe-(inline|eval)'" --type ts --type js --type html "${IGNORE[@]}" "${INTEL_GLOBS[@]}" > "$TMP" 2>/dev/null || true
UNSAFE_COUNT=$(wc -l < "$TMP" || echo 0)
if [ "$UNSAFE_COUNT" -gt 0 ]; then
  while IFS=: read -r file line content; do
    [ -z "$file" ] && continue
    add_finding "high" "CSP unsafe-*: $(echo "$content" | xargs | cut -c1-80)" "$file" "$line"
  done < "$TMP"
  log_warn "$UNSAFE_COUNT CSP com unsafe-* (revisar)"
fi
rm -f "$TMP"

CRITS=$(printf '%s\n' "${FINDINGS[@]}" | grep -c '"severity":"crit"')
HIGHS=$(printf '%s\n' "${FINDINGS[@]}" | grep -c '"severity":"high"')
if [ "$CRITS" -gt 0 ] || [ "$HIGHS" -gt 0 ]; then
  emit_result "$BLINDAR_AGENT" "failed" 1
  exit 1
fi

emit_result "$BLINDAR_AGENT" "passed" 0
exit 0
