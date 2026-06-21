#!/usr/bin/env bash
BLINDAR_AGENT="check-user-journey-simulator"
source "$(dirname "$0")/_lib.sh"
source "$(dirname "$0")/_api_wrapper.sh"
log_section "Check: user-journey-simulator (cenários por perfil)"

# Coleta pistas de perfis
EVIDENCE=""
[ -f "prisma/schema.prisma" ] && EVIDENCE+="=== schema ===\n$(head -c 5000 prisma/schema.prisma)\n\n"
[ -f "README.md" ] && EVIDENCE+="=== README ===\n$(head -c 3000 README.md)\n\n"

# Roles/permissions
ROLES=$(rg -nE "(@Roles|UserType|enum Role|role:)" --type ts '!node_modules' 2>/dev/null | head -30)
[ -n "$ROLES" ] && EVIDENCE+="=== roles/permissions ===\n$ROLES\n\n"

# Rotas
ROUTES=$(rg -nE "(<Route|router\.get|@Get\(|path:)" --type ts --type tsx '!node_modules' 2>/dev/null | head -40)
[ -n "$ROUTES" ] && EVIDENCE+="=== rotas (sample) ===\n$ROUTES\n\n"

if [ -z "$EVIDENCE" ]; then
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

SYSTEM="Você é o agente user-journey-simulator do blindar.
Detecte perfis de usuário existentes. Para cada um, simule 5-8 cenários
canônicos (cadastro, login, fluxo principal, suporte, cancelamento).
Identifique fricções, gargalos, gaps. Não invente perfis. Fix concreto sempre.
Foque em UX/produto, NÃO bugs de código (outros agentes cobrem)."

blindar_api_check "$BLINDAR_AGENT" "$SYSTEM" "$EVIDENCE

Detecte perfis e simule jornadas. Reporte fricções por cenário."
