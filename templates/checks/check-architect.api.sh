#!/usr/bin/env bash
# Wrapper API: architect — revisão de decisões arquiteturais
BLINDAR_AGENT="check-architect"
source "$(dirname "$0")/_lib.sh"
source "$(dirname "$0")/_api_wrapper.sh"

log_section "Check: architect (decisões arquiteturais via Claude API)"

# Coleta: README, package.json, prisma/schema, estrutura de pastas
EVIDENCE=""
[ -f "README.md" ] && EVIDENCE+="=== README.md ===\n$(head -c 5000 README.md)\n\n"
[ -f "package.json" ] && EVIDENCE+="=== package.json ===\n$(head -c 3000 package.json)\n\n"
[ -f "prisma/schema.prisma" ] && EVIDENCE+="=== prisma/schema.prisma ===\n$(head -c 5000 prisma/schema.prisma)\n\n"
if command -v find >/dev/null 2>&1; then
  EVIDENCE+="=== Estrutura (top-level) ===\n$(find . -maxdepth 2 -type d ! -path '*/node_modules*' ! -path '*/.git*' 2>/dev/null | head -30)\n"
fi
[ -f "${BLINDAR_DIR:-.blindar}/scan.json" ] && EVIDENCE+="=== Stack scan ===\n$(cat ${BLINDAR_DIR:-.blindar}/scan.json)\n\n"

if [ -z "$EVIDENCE" ]; then
  log_warn "Sem evidência coletável"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

SYSTEM="Você é o agente architect do blindar.
Avalie decisões arquiteturais do projeto:
- Boundaries claras entre módulos?
- Acoplamento e coesão adequados?
- Stack apropriada pro propósito?
- Trade-offs documentados?
- Scaling path claro?

Reporte gaps ou riscos arquiteturais — não bugs de implementação."

blindar_api_check "$BLINDAR_AGENT" "$SYSTEM" "$EVIDENCE"
