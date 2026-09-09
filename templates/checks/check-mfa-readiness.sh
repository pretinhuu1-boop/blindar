#!/usr/bin/env bash
# Materializa: mfa-readiness — senha sozinha já não segura conta que importa.
#
# Credencial vazada não é hipótese: é o vetor mais usado, e vem pronta de outro
# site onde a pessoa repetiu a senha. Rate limit e bloqueio por tentativa ajudam
# contra força bruta e não fazem nada contra credential stuffing — ali a senha
# está certa.
#
# O check não exige MFA obrigatório para todo mundo. Exige que ele EXISTA como
# opção, ao menos para quem tem poder administrativo. Conta de operador sem
# segundo fator é uma senha entre o atacante e o banco inteiro.
BLINDAR_AGENT="check-mfa-readiness"
source "$(dirname "$0")/_lib.sh"
log_section "Check: segundo fator disponível (TOTP / WebAuthn / passkey)"

# Só se aplica onde existe login de usuário.
# O achado precisa apontar para CÓDIGO. Sem o filtro, o primeiro acerto costuma
# ser o `.env.example` — o arquivo certo para saber que há login, e o errado para
# quem vai implementar o segundo fator.
LOGIN=$(scan_src '(/login|/signin|/sign-in|/auth/login|passport\.authenticate|signIn\(|bcrypt\.compare|argon2\.verify|check_password|authenticate_user|NextAuth|next-auth|lucia-auth|@auth/core)' \
  | grep -viE '\.(env|md|txt|ya?ml|json|lock)[^:]*:' | head -3)
[ -z "$LOGIN" ] && LOGIN=$(scan_src '(/login|/signin|/auth/login|bcrypt\.compare|argon2\.verify|check_password)' | head -1)
if [ -z "$LOGIN" ]; then
  log_info "sem fluxo de login de usuário — não se aplica"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi
ARQ=$(printf '%s\n' "$LOGIN" | head -1 | cut -d: -f1)
LN=$(printf '%s\n' "$LOGIN" | head -1 | cut -d: -f2)

# Segundo fator em qualquer forma legítima.
MFA=$(scan_src '(otplib|speakeasy|pyotp|totp|TOTP|two[_-]?factor|twoFactor|2fa|mfa_?(secret|enabled|code)|MFA|webauthn|WebAuthn|@simplewebauthn|passkey|fido2|authenticator_?secret|verify_?otp)' | head -3)
# Delegar a um IdP que já faz MFA também resolve — não é dever da aplicação
# reimplementar o que o provedor de identidade oferece.
#
# O padrão exige forma de PACOTE ou import, não o nome solto. A versão ingênua
# procurava `entra` — que é uma palavra portuguesa comum — e casou com a prosa de
# um `.accept-risk.md` num projeto real, transformando "login com bcrypt e sem
# segundo fator" em "delegado a IdP". O achado grave virou aviso por causa de um
# verbo.
IDP=$(scan_src '(@auth0/|auth0-js|["'"'"']auth0["'"'"']|@clerk/|@okta/|okta-auth-js|keycloak-js|keycloak-connect|amazon-cognito|client-cognito|@azure/msal|next-auth|@auth/core|@workos-inc|firebase/auth|@supabase/auth|@logto/)' | head -1)

if [ -n "$MFA" ]; then
  log_pass "segundo fator implementado ($(printf '%s\n' "$MFA" | head -1 | cut -d: -f1))"
elif [ -n "$IDP" ]; then
  log_pass "autenticação delegada a IdP ($(printf '%s\n' "$IDP" | head -1 | cut -d: -f1)) — o segundo fator é configuração lá"
  add_finding "low" \
    "Autenticação delegada a provedor de identidade: confirme no painel dele que o MFA está EXIGIDO, ao menos para contas administrativas. Delegar não liga o segundo fator sozinho." \
    "$(printf '%s\n' "$IDP" | head -1 | cut -d: -f1)" ""
else
  add_finding "med" \
    "Login com senha e nenhum segundo fator disponível (TOTP, WebAuthn/passkey ou IdP com MFA). Rate limit protege contra força bruta e não faz nada contra credential stuffing — ali a senha está certa, porque vazou de outro site. Ofereça ao menos TOTP e exija para contas administrativas." \
    "$ARQ" "$LN"
fi

if [ "${#FINDINGS[@]}" -gt 0 ]; then
  emit_result "$BLINDAR_AGENT" "failed" 0
  exit 0
fi
emit_result "$BLINDAR_AGENT" "passed" 0
exit 0
