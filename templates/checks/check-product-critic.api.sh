#!/usr/bin/env bash
BLINDAR_AGENT="check-product-critic"
source "$(dirname "$0")/_lib.sh"
source "$(dirname "$0")/_api_wrapper.sh"
log_section "Check: product-critic (adversarial sobre produto)"

EVIDENCE=""
[ -f "README.md" ] && EVIDENCE+="=== README ===\n$(head -c 3000 README.md)\n\n"

# Component sample
COMPONENTS=$(find src/components app/components components 2>/dev/null | head -20)
[ -n "$COMPONENTS" ] && EVIDENCE+="=== components ===\n$COMPONENTS\n\n"

# Routes
ROUTES=$(rg -n "(<Route|path:|router\.)" --type ts --type tsx '!node_modules' 2>/dev/null | head -30)
[ -n "$ROUTES" ] && EVIDENCE+="=== routes ===\n$ROUTES\n\n"

# Forms
FORMS=$(rg -n "(<form|onSubmit|useForm)" --type ts --type tsx '!node_modules' 2>/dev/null | head -20)
[ -n "$FORMS" ] && EVIDENCE+="=== forms (sample) ===\n$FORMS\n\n"

# Botões destrutivos
DESTR=$(rg -n "(delete|remove|destroy)" --type ts --type tsx '!node_modules' 2>/dev/null | head -20)
[ -n "$DESTR" ] && EVIDENCE+="=== destructive (sample) ===\n$DESTR\n\n"

if [ -z "$EVIDENCE" ]; then
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

SYSTEM="Você é o agente product-critic do blindar.
Aja como PO adversarial. Questione fluxos, inconsistências, over/under-engineering,
telas órfãs, dark patterns. NÃO faça code review (outros agentes cobrem).
Cada finding precisa de fix CONCRETO. Não confunda gosto pessoal com problema real.
Ignore contexto = erro. Justifique cada crítica."

blindar_api_check "$BLINDAR_AGENT" "$SYSTEM" "$EVIDENCE

Critique o produto. Aponte gaps reais com fix."
