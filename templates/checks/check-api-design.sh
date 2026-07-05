#!/usr/bin/env bash
# Materializa agente: api-design
# OpenAPI spec presente, RFC 7807 errors, idempotency em POST

BLINDAR_AGENT="check-api-design"
source "$(dirname "$0")/_lib.sh"

log_section "Check: api-design (OpenAPI + RFC 7807 + idempotency)"

if ! command -v rg >/dev/null 2>&1; then
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

# Roda só se for backend (NestJS / Express / FastAPI / Fastify)
BACKEND=0
for lib in "@nestjs/core" express fastify "@fastify/cors" "fastapi"; do
  if grep -qE "\"$lib\":" package.json pyproject.toml requirements.txt 2>/dev/null; then
    BACKEND=1
  fi
done
if [ "$BACKEND" -eq 0 ]; then
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

IGNORE=(-g '!node_modules' -g '!dist' -g '!build' -g '!**/*.test.*')
load_intelligence_globs "$BLINDAR_AGENT"
FAIL=0

# 1. OpenAPI / Swagger setup detectado
log_info "Verificando OpenAPI spec..."
if has_file "openapi.yaml" || has_file "openapi.json" || has_file "swagger.json"; then
  log_pass "OpenAPI spec presente"
elif grep -qE "@nestjs/swagger|swagger-jsdoc|fastify-swagger|@fastify/swagger" package.json 2>/dev/null; then
  log_pass "Swagger/OpenAPI integration detectado"
else
  add_finding "high" "Sem OpenAPI/Swagger setup — clientes não têm contract" "" ""
  log_warn "Sem OpenAPI"
fi

# 2. Spectral lint em CI (se openapi.yaml existe)
if has_file "openapi.yaml" || has_file "openapi.json"; then
  if ! grep -rqE "spectral|@stoplight/spectral" .github/workflows/ 2>/dev/null; then
    add_finding "med" "OpenAPI sem Spectral lint em CI — quebras não detectadas" ".github/workflows/" ""
  fi
fi

# 3. Idempotency-Key em POST críticos (já coberto por check-payments, aqui é genérico)
log_info "Verificando idempotency em POST..."
TMP=$(mktemp)
rg -n "@Post\(['\"]/?(payments|orders|charges)" --type ts "${IGNORE[@]}" "${INTEL_GLOBS[@]}" -A 10 2>/dev/null > "$TMP" || true
# Verifica se há header Idempotency-Key próximo
if [ -s "$TMP" ] && ! grep -qE "(Idempotency-Key|idempotency)" "$TMP"; then
  add_finding "high" "Endpoint crítico (payments/orders) sem header Idempotency-Key" "" ""
fi
rm -f "$TMP"

# 4. RFC 7807 Problem Details em errors
log_info "Verificando formato de erro..."
if ! rg -l "(application/problem\+json|ProblemDetails|@RFC7807)" --type ts --type js "${IGNORE[@]}" "${INTEL_GLOBS[@]}" 2>/dev/null | head -1 | grep -q .; then
  add_finding "med" "Erros não no formato RFC 7807 (application/problem+json)" "" ""
fi

# 5. Paginação cursor em endpoints públicos
log_info "Verificando pagination..."
TMP=$(mktemp)
rg -n "skip\s*:\s*Number|offset\s*:\s*Number|page\s*:\s*Number" --type ts "${IGNORE[@]}" "${INTEL_GLOBS[@]}" > "$TMP" 2>/dev/null || true
OFFSET=$(wc -l < "$TMP" || echo 0)
if [ "$OFFSET" -gt 5 ]; then
  add_finding "low" "$OFFSET endpoint(s) com offset pagination — preferir cursor pra escala" "" ""
fi
rm -f "$TMP"

# 6. Status code apropriado (não 200 com {success:false})
log_info "Buscando anti-pattern 200 com success:false..."
TMP=$(mktemp)
rg -n "status\(200\)\.json\(\{\s*success:\s*false" --type ts --type js "${IGNORE[@]}" "${INTEL_GLOBS[@]}" > "$TMP" 2>/dev/null || true
WRONG_STATUS=$(wc -l < "$TMP" || echo 0)
if [ "$WRONG_STATUS" -gt 0 ]; then
  add_finding "high" "$WRONG_STATUS endpoint(s) retornando 200 com {success:false} — usar 4xx/5xx apropriado" "" ""
fi
rm -f "$TMP"

# 7. Webhook signature verify (genérico)
log_info "Buscando webhook handler..."
TMP=$(mktemp)
rg -l "@Post.*webhook|router\.post.*webhook" --type ts --type js "${IGNORE[@]}" "${INTEL_GLOBS[@]}" > "$TMP" 2>/dev/null || true
if [ -s "$TMP" ]; then
  WEBHOOKS=$(wc -l < "$TMP" || echo 0)
  VERIFIED=$(rg -l "(constructEvent|verifyHmac|verifySignature|x-signature)" --type ts --type js "${IGNORE[@]}" "${INTEL_GLOBS[@]}" 2>/dev/null | wc -l || echo 0)
  if [ "$WEBHOOKS" -gt 0 ] && [ "$VERIFIED" -eq 0 ]; then
    add_finding "crit" "Webhook(s) detectado(s) sem signature verify" "" ""
    log_fail "Webhook sem signature verify"
    FAIL=1
  fi
fi
rm -f "$TMP"

if [ "$FAIL" -eq 1 ]; then
  emit_result "$BLINDAR_AGENT" "failed" 1
  exit 1
fi

emit_result "$BLINDAR_AGENT" "passed" 0
exit 0
