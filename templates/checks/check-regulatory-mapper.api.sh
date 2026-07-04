#!/usr/bin/env bash
# Wrapper API: regulatory-mapper — mapeia normas/leis/NRs/regras que fazem sentido
# pra ESTE projeto (setor + dados + geografia) e o que precisa seguir.
BLINDAR_AGENT="check-regulatory-mapper"
source "$(dirname "$0")/_lib.sh"
source "$(dirname "$0")/_api_wrapper.sh"
log_section "Check: regulatory-mapper (normas/leis/NRs aplicáveis)"

EVIDENCE=""
[ -f "README.md" ] && EVIDENCE+="=== README.md ===\n$(head -c 5000 README.md)\n\n"
[ -f "package.json" ] && EVIDENCE+="=== package.json ===\n$(head -c 2500 package.json)\n\n"
[ -f "pyproject.toml" ] && EVIDENCE+="=== pyproject.toml ===\n$(head -c 2000 pyproject.toml)\n\n"
[ -f ".blindar/graph.json" ] && EVIDENCE+="=== grafo (models/endpoints/env) ===\n$(head -c 5000 .blindar/graph.json)\n\n"
# Sinais de setor/dado sensível
if command -v rg >/dev/null 2>&1; then
  EVIDENCE+="=== sinais de domínio ===\n"
  EVIDENCE+="$(rg -oi "(cpf|cnpj|pix|boleto|cart[aã]o|payment|stripe|health|paciente|prontu[aá]rio|fhir|hl7|banc|financ|lgpd|gdpr|hipaa|pci|menor|crian[çc]a|biometl?r|geolocation)" --type ts --type js --type py --type md -g '!node_modules' 2>/dev/null | sort -u | head -40)\n"
fi

if [ -z "$EVIDENCE" ]; then
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

SYSTEM="Você é o agente regulatory-mapper do blindar. Dado o projeto (domínio,
dados manipulados, geografia), LISTE as normas/leis/regulamentos/NRs que fazem
sentido verificar e o que precisa seguir. Seja específico ao projeto — não
despeje tudo.

Considere (quando aplicável ao que os sinais mostram):
- Dados pessoais (Brasil): LGPD + regulamentos ANPD; dados de criança/adolescente
  (ECA + fiscalização ANPD 2026); base legal, retenção, DPO, RIPD.
- Dados pessoais (global): GDPR (UE), CCPA (Califórnia); SCC pra transferência
  internacional (obrigatória).
- Pagamentos/cartão: PCI-DSS; open finance/BACEN se for financeiro BR.
- Saúde: HIPAA (EUA), FHIR/HL7; dados sensíveis de saúde na LGPD.
- Acessibilidade: WCAG 2.2 AA; eMAG/Lei Brasileira de Inclusão se gov/BR.
- Trabalho/segurança (se houver operação física/RH): NRs aplicáveis
  (ex.: NR-1 GRO, NR-17 ergonomia pra trabalho em telas).
- Setoriais: Marco Civil da Internet, notificação de breach (ANPD: 3 dias úteis).

Para cada norma aplicável: severity (risco de não cumprir), message (norma +
por que se aplica a ESTE projeto), fix (o requisito concreto a seguir).
Se um sinal é ambíguo, diga o que confirmar. NÃO liste norma sem nexo com o projeto."

blindar_api_check "$BLINDAR_AGENT" "$SYSTEM" "$EVIDENCE"
