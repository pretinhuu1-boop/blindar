#!/usr/bin/env bash
# Materializa: strategic-scanner (Fase 0 — detecção de stack)
# Sempre passa — output é puramente informativo, gravado em .blindar/scan.json
BLINDAR_AGENT="check-strategic-scanner"
source "$(dirname "$0")/_lib.sh"
log_section "Check: strategic-scanner (stack discovery)"

SCAN_OUT="${BLINDAR_DIR:-.blindar}/scan.json"
mkdir -p "$(dirname "$SCAN_OUT")"

# Detecta stack
declare -a FRAMEWORKS=() DATABASES=() RUNTIMES=() FEATURES=()

is_nodejs && RUNTIMES+=("node")
is_python && RUNTIMES+=("python")
is_go      && RUNTIMES+=("go")
is_rust    && RUNTIMES+=("rust")

is_nextjs && FRAMEWORKS+=("nextjs")
is_nestjs && FRAMEWORKS+=("nestjs")
[ -f "vite.config.ts" ] || [ -f "vite.config.js" ] && FRAMEWORKS+=("vite")
[ -f "remix.config.js" ] && FRAMEWORKS+=("remix")
[ -f "astro.config.mjs" ] && FRAMEWORKS+=("astro")
[ -f "svelte.config.js" ] && FRAMEWORKS+=("svelte")
[ -f "nuxt.config.ts" ] && FRAMEWORKS+=("nuxt")

is_prisma && DATABASES+=("postgres+prisma")
grep -qE "\"mongodb\":" package.json 2>/dev/null && DATABASES+=("mongodb")
grep -qE "\"@supabase/" package.json 2>/dev/null && DATABASES+=("supabase")
grep -qE "(redis|ioredis|bullmq)" package.json 2>/dev/null && DATABASES+=("redis")

# Features
grep -qE "\"stripe\":" package.json 2>/dev/null && FEATURES+=("payments-stripe")
grep -qE "\"openai\":|\"@anthropic-ai/" package.json 2>/dev/null && FEATURES+=("ai-llm")
grep -qE "(socket\.io|ws|@trpc)" package.json 2>/dev/null && FEATURES+=("realtime")
grep -qE "tenantId|tenant_id" prisma/schema.prisma 2>/dev/null && FEATURES+=("multi-tenant")
[ -f "next.config.ts" ] && grep -qE "i18n" next.config.* 2>/dev/null && FEATURES+=("i18n")

# Output JSON
cat > "$SCAN_OUT" <<EOF
{
  "schema": "blindar/scan@v1",
  "ran_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "runtimes": [$(printf '"%s",' "${RUNTIMES[@]}" | sed 's/,$//')],
  "frameworks": [$(printf '"%s",' "${FRAMEWORKS[@]}" | sed 's/,$//')],
  "databases": [$(printf '"%s",' "${DATABASES[@]}" | sed 's/,$//')],
  "features": [$(printf '"%s",' "${FEATURES[@]}" | sed 's/,$//')],
  "is_ui": $([ "${#FRAMEWORKS[@]}" -gt 0 ] && echo true || echo false),
  "is_api": $((is_nestjs || grep -qE '"express":|"fastify":' package.json 2>/dev/null) && echo true || echo false),
  "is_multi_tenant": $(grep -qE "tenantId|tenant_id" prisma/schema.prisma 2>/dev/null && echo true || echo false)
}
EOF

log_info "Stack detectado:"
log_info "  Runtimes: ${RUNTIMES[*]:-none}"
log_info "  Frameworks: ${FRAMEWORKS[*]:-none}"
log_info "  Databases: ${DATABASES[*]:-none}"
log_info "  Features: ${FEATURES[*]:-none}"
log_info "Scan salvo em: $SCAN_OUT"

emit_result "$BLINDAR_AGENT" "passed" 0
