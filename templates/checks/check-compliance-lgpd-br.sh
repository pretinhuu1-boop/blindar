#!/usr/bin/env bash
# Materializa: compliance-lgpd-br — DPO, política, runbook 72h, gates Art. 14/18
BLINDAR_AGENT="check-compliance-lgpd-br"
source "$(dirname "$0")/_lib.sh"
log_section "Check: LGPD/ANPD (Brasil)"

if ! command -v rg >/dev/null 2>&1; then emit_result "$BLINDAR_AGENT" "skipped" 0; exit 0; fi

# Detecta PII brasileira (CPF, CEP, RG)
HAS_BR_PII=$(rg -lE "(cpf|cnpj|cep|rg)" --type ts --type prisma 2>/dev/null | head -1)
if [ -z "$HAS_BR_PII" ]; then
  emit_result "$BLINDAR_AGENT" "skipped" 0; exit 0
fi

# 1. Política de privacidade
[ ! -f "docs/lgpd/politica-privacidade.md" ] && [ ! -f "PRIVACY.md" ] && \
  [ ! -f "public/privacy.md" ] && \
  add_finding "high" "Sem política de privacidade — LGPD Art. 9 violação" "" ""

# 2. Runbook breach notification 72h (ANPD desde 2024 é 3 dias úteis)
[ ! -f "docs/runbooks/breach-notification.md" ] && [ ! -f "docs/lgpd/incidente-anpd.md" ] && \
  add_finding "med" "Sem runbook breach notification — ANPD exige 3 dias úteis" "" ""

# 3. 6 endpoints LGPD Art. 18 (acesso/correção/exclusão/portabilidade/anonimização/oposição)
LGPD_ENDPOINTS=$(rg -cE "/api/lgpd/|/lgpd/(export|delete|access|correct|anonymize|opposition)" --type ts 2>/dev/null | wc -l || echo 0)
if [ "$LGPD_ENDPOINTS" -lt 4 ]; then
  add_finding "high" "$LGPD_ENDPOINTS endpoints LGPD detectados (esperado 6 — Art. 18)" "" ""
fi

# 4. DPO email/contato público
HAS_DPO=$(grep -rlE "dpo@|encarregado@" public/ docs/ src/ 2>/dev/null | head -1)
[ -z "$HAS_DPO" ] && add_finding "med" "Sem contato de DPO/encarregado público (LGPD Art. 41)" "" ""

# 5. Cookie banner real (opt-in)
HAS_BANNER=$(rg -lE "(cookie.*consent|cookieConsent|CookieBanner|Klaro)" --type tsx --type jsx 2>/dev/null | head -1)
if [ -z "$HAS_BANNER" ] && rg -lE "(analytics|gtag|fbq)" --type tsx 2>/dev/null | head -1 | grep -q .; then
  add_finding "high" "Analytics sem cookie banner — LGPD Art. 7-9 violação" "" ""
fi

# 6. Gate Art. 14 (menores) em cadastro
HAS_AGE_GATE=$(rg -nE "(birthDate|date_of_birth|idade).*[<>=]?\s*1[3-8]" --type ts 2>/dev/null | wc -l || echo 0)
if [ "$HAS_AGE_GATE" -eq 0 ]; then
  add_finding "low" "Sem gate de idade detectado — Art. 14 (menores) requer consent dos pais" "" ""
fi

# 7. Anonimização irreversível (não apenas deletedAt)
HAS_ANON=$(rg -lE "(anonymize|anonimiz|md5.*email|hash.*email).*lgpd" --type ts 2>/dev/null | head -1)
[ -z "$HAS_ANON" ] && add_finding "low" "Sem função de anonimização irreversível — direito ao esquecimento limitado" "" ""

emit_result "$BLINDAR_AGENT" "passed" 0
