#!/usr/bin/env bash
BLINDAR_AGENT="check-growth-opportunities"
source "$(dirname "$0")/_lib.sh"
source "$(dirname "$0")/_api_wrapper.sh"
log_section "Check: growth-opportunities (wishlist by best practices)"

EVIDENCE=""
[ -f "README.md" ] && EVIDENCE+="=== README ===\n$(head -c 4000 README.md)\n\n"
[ -f "package.json" ] && EVIDENCE+="=== package.json (deps) ===\n$(head -c 2000 package.json)\n\n"
[ -f "${BLINDAR_DIR:-.blindar}/scan.json" ] && EVIDENCE+="=== stack scan ===\n$(cat ${BLINDAR_DIR:-.blindar}/scan.json)\n\n"

if [ -z "$EVIDENCE" ]; then
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

SYSTEM="Você é o agente growth-opportunities do blindar.
Identifique a categoria do produto (SaaS, marketplace, CRM, etc.).
Liste 5-10 oportunidades top ordenadas por ROI. Categorias possíveis:
retenção, automação, self-service, analytics, IA aplicada, multi-canal,
operacional, trust/compliance, performance/UX, monetização.

Cada oportunidade: justificativa, complexity, prerequisite, exemplo concreto.
NÃO listar 50 genéricos. NÃO sugerir features fora do escopo do produto.
SEMPRE justificar ROI."

blindar_api_check "$BLINDAR_AGENT" "$SYSTEM" "$EVIDENCE

Categorize o produto e proponha top oportunidades."
