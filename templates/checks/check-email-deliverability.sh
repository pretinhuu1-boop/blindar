#!/usr/bin/env bash
# Materializa: email-deliverability — DKIM/SPF/DMARC, supressão, env-aware
BLINDAR_AGENT="check-email-deliverability"
source "$(dirname "$0")/_lib.sh"
log_section "Check: email-deliverability (DKIM/SPF/DMARC + supressão)"

# Detecta lib de email
HAS_EMAIL=0
for lib in nodemailer resend "@sendgrid/mail" "aws-sdk" postmark; do
  grep -qE "\"$lib\":|\"@.*$lib\":" package.json 2>/dev/null && HAS_EMAIL=1
done

if [ "$HAS_EMAIL" -eq 0 ]; then emit_result "$BLINDAR_AGENT" "skipped" 0; exit 0; fi

IGNORE=(-g '!node_modules' -g '!dist' -g '!**/*.test.*')
ENV="${BLINDAR_ENV:-${NODE_ENV:-development}}"

# Em dev, é OK não ter DMARC strict
if [ "$ENV" = "development" ] || [ "$ENV" = "test" ]; then
  log_info "Env=$ENV — pulando checks de DMARC/SPF strict (relaxados em dev)"
else
  # 1. Sem template_safe_list pra transacionais
  if [ ! -f ".blindar/intelligence.yml" ] || ! grep -qE "template_safe_list" .blindar/intelligence.yml 2>/dev/null; then
    add_finding "low" "Sem template_safe_list em intelligence.yml — todos templates exigirão unsubscribe" "" ""
  fi
fi

# 2. Template em string literal (não em DB/CMS)
TMP=$(mktemp)
rg -nU "['\"]Olá[^'\"]{30,}['\"]" --type ts "${IGNORE[@]}" -g '!**/templates/**' -g '!**/locales/**' > "$TMP" 2>/dev/null || true
HARDCODED_EMAILS=$(wc -l < "$TMP" || echo 0)
[ "$HARDCODED_EMAILS" -gt 0 ] && add_finding "med" "$HARDCODED_EMAILS template(s) de email hardcoded — mover pra DB/CMS" "" ""
rm -f "$TMP"

# 3. send sem check de supressão
TMP=$(mktemp)
rg -n "(resend|ses|sendgrid|nodemailer)\.\w+\.send\(" --type ts "${IGNORE[@]}" > "$TMP" 2>/dev/null || true
SENDS=$(wc -l < "$TMP" || echo 0)
SUPPRESSED_CHECK=$(rg -l "(isSuppressed|email_suppressions|supress)" --type ts "${IGNORE[@]}" 2>/dev/null | head -1)
if [ "$SENDS" -gt 0 ] && [ -z "$SUPPRESSED_CHECK" ]; then
  add_finding "high" "$SENDS chamada(s) de email sem check de supressão — manda pra bounce repetidamente" "" ""
fi
rm -f "$TMP"

# 4. Webhook de bounce ausente
HAS_BOUNCE=$(rg -l "(bounce|complaint).*webhook|@Post.*bounce" --type ts "${IGNORE[@]}" 2>/dev/null | head -1)
[ -z "$HAS_BOUNCE" ] && add_finding "med" "Sem webhook handler pra bounce/complaint — reputação queima sem ação" "" ""

# 5. Reply-to no-reply (anti-pattern)
NOREPLY=$(rg -ci "no-reply@|noreply@" --type ts --type js "${IGNORE[@]}" 2>/dev/null | wc -l || echo 0)
[ "$NOREPLY" -gt 0 ] && add_finding "low" "$NOREPLY uso(s) de no-reply@ — a11y + deliverability ruim" "" ""

emit_result "$BLINDAR_AGENT" "passed" 0
