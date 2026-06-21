#!/usr/bin/env bash
BLINDAR_AGENT="check-feature-gap-analyzer"
source "$(dirname "$0")/_lib.sh"
source "$(dirname "$0")/_api_wrapper.sh"
log_section "Check: feature-gap-analyzer (gaps entre camadas)"

EVIDENCE=""
[ -f "prisma/schema.prisma" ] && EVIDENCE+="=== schema ===\n$(head -c 6000 prisma/schema.prisma)\n\n"
[ -f "package.json" ] && EVIDENCE+="=== package.json ===\n$(head -c 2000 package.json)\n\n"

# Endpoints
ENDP=$(rg -nE "(@(Get|Post|Put|Delete|Patch)|router\.(get|post)|app\.(get|post))" --type ts '!node_modules' 2>/dev/null | head -40)
[ -n "$ENDP" ] && EVIDENCE+="=== endpoints ===\n$ENDP\n\n"

# Components
COMP=$(find src/components app/components components 2>/dev/null | head -30)
[ -n "$COMP" ] && EVIDENCE+="=== components ===\n$COMP\n\n"

# Tests
TESTS=$(find tests __tests__ e2e -name "*.test.*" -o -name "*.spec.*" 2>/dev/null | head -20)
EVIDENCE+="=== tests count ===\n$(echo "$TESTS" | wc -l)\n\n"

# Feature flags
FLAGS=$(rg -nE "(feature_flag|flagsmith|growthbook|process\.env\.FEATURE)" --type ts '!node_modules' 2>/dev/null | head -10)
[ -n "$FLAGS" ] && EVIDENCE+="=== flags ===\n$FLAGS\n\n"

if [ -z "$EVIDENCE" ]; then
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

SYSTEM="Você é o agente feature-gap-analyzer do blindar.
Identifique features PARCIAIS: schema sem endpoint, endpoint sem UI,
UI sem validação, soft-delete sem restore, audit log não exposto, flag morta.
Foco em gaps específicos com fix mínimo. Sempre estime complexity."

blindar_api_check "$BLINDAR_AGENT" "$SYSTEM" "$EVIDENCE

Cruze camadas e reporte gaps."
