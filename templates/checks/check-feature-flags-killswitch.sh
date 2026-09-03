#!/usr/bin/env bash
# Materializa: feature-flags-killswitch — dá para desligar sem deploy?
#
# Sem kill switch, a única forma de tirar do ar um recurso que quebrou é um
# deploy de reversão: build, pipeline, fila de aprovação — dez a quarenta minutos
# com o problema no ar. Com flag lida em runtime, é um toggle.
#
# A distinção que importa: `const NOVO_CHECKOUT = true` NÃO é flag. É constante
# de build. Ela só muda com o mesmo deploy que você está tentando evitar.
BLINDAR_AGENT="check-feature-flags-killswitch"
source "$(dirname "$0")/_lib.sh"
log_section "Check: kill switch / rollout gradual"

# Só faz sentido em coisa que fica no ar. Lib e CLI não têm o que desligar
# em runtime — o usuário atualiza a versão quando quiser.
if ! scan_hit 'express|fastify|next|nestjs|@nestjs|koa|hapi|flask|django|fastapi|gin-gonic|rails|http\.createServer|app\.listen'; then
  log_info "sem serviço que fique no ar — não há o que desligar em runtime"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

# Sistema de flag dedicado (remoto: muda sem deploy).
SISTEMA=$(scan_src 'unleash|launchdarkly|LaunchDarkly|flagsmith|growthbook|configcat|@vercel/flags|isFeatureEnabled' | head -3)
# Flag lida do ambiente ou do banco em runtime — vale como kill switch.
RUNTIME=$(scan_src 'process\.env\.(FEATURE|FF|ENABLE|KILL|DISABLE)_|process\.env\[[^]]*(FEATURE|FF_|ENABLE|KILL|DISABLE)|environ\[.(FEATURE|FF|ENABLE|KILL|DISABLE)|getFlag\(|isEnabled\(|feature_?flags?\.(get|find|findFirst)|from feature_flags' | head -3)
# Constante de build fingindo de flag.
CONSTANTE=$(scan_src '^[[:space:]]*(export )?(const|let|var)[[:space:]]+[A-Z_]*(FEATURE|ENABLE|USE_NEW|FLAG)[A-Z_]*[[:space:]]*=[[:space:]]*(true|false)' | head -3)

if [ -z "$SISTEMA" ] && [ -z "$RUNTIME" ]; then
  if [ -n "$CONSTANTE" ]; then
    ARQ=$(printf '%s\n' "$CONSTANTE" | head -1 | cut -d: -f1)
    LN=$(printf '%s\n' "$CONSTANTE" | head -1 | cut -d: -f2)
    add_finding "med" \
      "Flag existe como CONSTANTE de build, não como chave de runtime — desligar o recurso exige exatamente o deploy que a flag deveria tornar desnecessário." "$ARQ" "$LN"
  else
    add_finding "med" \
      "Sem kill switch: nenhum sistema de flag (Unleash/LaunchDarkly/Flagsmith/GrowthBook/ConfigCat) nem flag lida do ambiente ou do banco em runtime. Recurso novo que quebrar só sai do ar com deploy de reversão — dez a quarenta minutos de incidente que um toggle resolveria em segundos." "" ""
  fi
else
  log_pass "kill switch presente (flag lida em runtime)"
  if [ -n "$CONSTANTE" ]; then
    ARQ=$(printf '%s\n' "$CONSTANTE" | head -1 | cut -d: -f1)
    LN=$(printf '%s\n' "$CONSTANTE" | head -1 | cut -d: -f2)
    add_finding "low" "Há kill switch, mas também flag hardcoded como constante de build — essa não desliga sem deploy" "$ARQ" "$LN"
  fi
fi

if [ "${#FINDINGS[@]}" -gt 0 ]; then
  emit_result "$BLINDAR_AGENT" "failed" 0
  exit 0
fi
emit_result "$BLINDAR_AGENT" "passed" 0
exit 0
