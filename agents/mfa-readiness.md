---
name: mfa-readiness
category: security
module: 2
priority: P1
lead: security-lead
authority: implement
description: |
  Segundo fator disponível (TOTP, WebAuthn/passkey ou IdP com MFA) em projeto que tem login. Rate limit protege contra força bruta e não faz nada contra credential stuffing — ali a senha está certa. Auto-skip sem login.
---

# Agent: mfa-readiness

Credencial vazada não é hipótese: é o vetor mais usado, e vem pronta de outro site
onde a pessoa repetiu a senha.

Rate limit e bloqueio por tentativa ajudam contra força bruta e **não fazem nada**
contra credential stuffing — ali a senha está certa, o login parece legítimo, e
nenhum contador dispara. O único controle que muda o resultado é exigir algo que
o atacante não tem.

Este check não exige MFA obrigatório para todo mundo. Exige que ele **exista como
opção**, e sinaliza que contas com poder administrativo deveriam ser obrigadas.
Conta de operador sem segundo fator é uma senha entre o atacante e o banco
inteiro.

## O que o check já garante

[`check-mfa-readiness.sh`](../templates/checks/check-mfa-readiness.sh):

| Situação | Severidade |
|---|---|
| Login com senha e nenhum segundo fator disponível | **med** |
| Autenticação delegada a IdP (confirmar exigência no painel) | **low** |

Aceita: `otplib`, `speakeasy`, `pyotp`, TOTP, `@simplewebauthn`, passkey, FIDO2,
ou delegação a Auth0, Clerk, Okta, Keycloak, Cognito, Entra, WorkOS, Firebase
Auth, Supabase Auth, Logto.

Auto-skip em projeto sem fluxo de login.

## A ordem de preferência

1. **Passkey / WebAuthn** — resistente a phishing por construção: a credencial é
   ligada à origem, e um site clonado não consegue usá-la. É o único fator que
   resolve o problema em vez de encarecê-lo.
2. **TOTP** (app autenticador) — barato, offline, sem custo por uso. O padrão
   razoável para quem não vai implementar WebAuthn agora.
3. **SMS** — melhor que nada e pior que os dois acima: SIM swap é real, e cada
   código custa dinheiro (ver [`metered-external-cost-guard`](metered-external-cost-guard.md)).

## Os detalhes que costumam ficar de fora

- **Código de recuperação** gerado no cadastro do fator, mostrado uma vez. Sem
  ele, perder o celular vira ticket de suporte com verificação manual de
  identidade — que é o elo mais fraco de todos.
- **Reautenticação em operação sensível**, não só no login: trocar e-mail,
  trocar senha, gerar chave de API.
- **Sessão existente não vira MFA retroativo.** Ligar o segundo fator sem
  invalidar sessões deixa o atacante que já entrou lá dentro.
- **Rate limit no próprio código TOTP** — seis dígitos são 10⁶, e sem limite dá
  para chutar.

## O que só se prova fora do repositório

| Verificar | Por quê |
|---|---|
| MFA **exigido** para administradores | disponível ≠ obrigatório |
| Fluxo de recuperação não contorna o fator | "esqueci o código" que só pede e-mail anula tudo |
| Deriva de relógio tratada | TOTP com janela de zero rejeita usuário legítimo |
