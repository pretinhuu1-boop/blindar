#!/usr/bin/env bash
# Materializa: rate-limit (ASVS V11.3)
BLINDAR_AGENT="check-rate-limit"
source "$(dirname "$0")/_lib.sh"
log_section "Check: rate-limit"

if ! command -v rg >/dev/null 2>&1; then emit_result "$BLINDAR_AGENT" "skipped" 0; exit 0; fi

IGNORE=(-g '!.next' -g '!.nuxt' -g '!out' -g '!.svelte-kit' -g '!node_modules' -g '!dist' -g '!**/*.test.*')
load_intelligence_globs "$BLINDAR_AGENT"

HAS_RL=$(rg -c "(rate-limit|rateLimit|@upstash/ratelimit|express-rate-limit|@nestjs/throttler|slowapi|Limiter\(|flask-limiter|django-ratelimit|ratelimit\()" --type ts --type js --type py "${IGNORE[@]}" "${INTEL_GLOBS[@]}" 2>/dev/null | wc -l || echo 0)
HAS_ROUTES=$(rg -c "(app\.(post|put|delete)|@Post\(|@Put\(|@Delete\(|@(app|router)\.(post|put|delete)\(|methods\s*=\s*\[[\"'](POST|PUT|DELETE))" --type ts --type py "${IGNORE[@]}" "${INTEL_GLOBS[@]}" 2>/dev/null | wc -l || echo 0)

if [ "$HAS_ROUTES" -gt 0 ] && [ "$HAS_RL" -eq 0 ]; then
  add_finding "high" "Rotas POST/PUT/DELETE sem rate-limit detectável" "" ""
  emit_result "$BLINDAR_AGENT" "failed" 1
  exit 1
fi

# Endpoints sensíveis sem rate limit explícito (login, signup, reset, otp)
SENSITIVE=$(rg -l "(login|signin|signup|register|reset.password|verify.otp|forgot.password)" --type ts --type py "${IGNORE[@]}" "${INTEL_GLOBS[@]}" 2>/dev/null | wc -l || echo 0)
# `-i` obrigatório: o padrão é minúsculo e o mundo real escreve `rateLimit`,
# `RateLimit`, `rate_limit`. Sem isso, um fixture que importa `rateLimit` e
# aplica `limiter` na rota de login era reportado como "endpoint sensível sem
# rate-limit dedicado".
#
# O falso positivo existia desde sempre e ninguém via, porque o check somava o
# achado `high` e emitia `passed` mesmo assim. Só apareceu quando o emit_result
# passou a recusar `passed` com crit/high: a incoerência entre status e achado
# estava escondendo o defeito no achado.
# Duas correções na mesma linha, e as duas davam FALSO POSITIVO — o check
# acusava "endpoint sensível sem rate-limit" num projeto que tem rate-limit:
#
#   1. `-i`. O padrão é minúsculo e o mundo real escreve `rateLimit`,
#      `RateLimit`, `rate_limit`.
#   2. sem `xargs`. No Windows o `rg -l` devolve `.\src\server.ts` com barra
#      invertida, e o `grep` do MSYS não abre esse caminho — a lista chegava
#      vazia e a contagem dava 0. O `2>/dev/null` escondia o erro.
#
# Nenhum dos dois aparecia, porque o check somava o achado `high` e emitia
# `passed` assim mesmo. Só ficou visível quando o emit_result passou a recusar
# `passed` com crit/high: a incoerência entre status e achado estava escondendo
# o defeito no achado.
SENSITIVE_RL=0
while IFS= read -r _arq; do
  [ -z "$_arq" ] && continue
  _arq="${_arq#./}"; _arq="${_arq#.\\}"
  grep -liE "(login|signup|reset|otp)" "$_arq" >/dev/null 2>&1 && SENSITIVE_RL=$((SENSITIVE_RL + 1))
done <<< "$(rg -li "(rate.?limit|limiter\.limit|@limiter|slowapi|Throttle)" --type ts --type py "${IGNORE[@]}" "${INTEL_GLOBS[@]}" 2>/dev/null || true)"

if [ "$SENSITIVE" -gt 0 ] && [ "$SENSITIVE_RL" -eq 0 ]; then
  add_finding "high" "Endpoint sensível (login/reset/otp) sem rate-limit dedicado" "" ""
fi

emit_result "$BLINDAR_AGENT" "passed" 0
