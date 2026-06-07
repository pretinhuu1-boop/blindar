# agent: access-control

Autenticação, autorização, sessão. Cobre técnica #1 do baseline de segurança
de TI (controle de acesso) e o controle "Acesso Lógico" da maioria dos
frameworks (ISO 27001 A.9, NIST CSF PR.AC, CIS Control 5/6).

## Quando ativar

Round cujo gap é da categoria `auth_session`, `web_api` (autz), ou qualquer
ATK marcado como **`crit` ou `high`** envolvendo identidade/permissões.

⚠ **Prioridade alta** — security-first: em empate de severidade com
outras categorias, este agente vence o pick.

## Prompt

```
Target: ATK-{XXX} ({severity}) — {title}. Vector: {vec}.

Audit dos vetores de acesso:
1. Senhas: complexidade mínima, hash (Argon2id ou bcrypt cost≥12, jamais
   SHA-x puro), rate-limit em login.
2. MFA: TOTP / WebAuthn / hardware key. TOTP precisa janela ≤30s + anti-reuse.
3. Sessão: token rotacionado pós-login, expiração, revogação server-side,
   bind a IP/UA quando possível.
4. RBAC: roles definidas, atribuição auditada, deny-by-default.
5. Least-privilege: cada usuário/serviço com o mínimo necessário.
6. Service accounts: credenciais separadas, rotacionáveis, sem login interativo.

Implement minimal change closing the vector (≤80 LOC):
- Test em tests/test_red{XXX}.py (happy + edge + attack: brute force,
  privilege escalation, session fixation).
- Grep estático: falha se endpoint novo sem decorator de auth/role.
- sec.html: ATK → covered, matrix recalc.

Backward compatible. Fail-closed (default-deny).
```

## Princípios não-negociáveis

- **Deny-by-default**. Endpoint novo sem decorator de role → grep falha.
- **Senha em texto = bug crítico.** Hash Argon2id ou bcrypt cost≥12.
- **MFA obrigatório** pra qualquer ação privilegiada. Recovery codes
  guardados hash, não plaintext.
- **Sessão revogável server-side.** JWT puro stateless não passa em prod —
  precisa lista de revogação ou rotação curta.
- **Privilege escalation test** em cada role nova. Teste prova que role A
  não acessa recurso de role B.
- **Brute-force protection** em login: rate-limit + lockout exponencial +
  alerta após N tentativas.

## Teste obrigatório (≥3 asserts)

- Happy: login válido + MFA → sessão criada
- Edge: senha trocada → sessão antiga revogada
- Attack: brute force 10x → lockout ativa; tentativa de elevation
  (user calls admin endpoint) → 403

## Mapeamento de frameworks

| Framework | Controle |
|---|---|
| ISO 27001 | A.9.1.x (Access control policy), A.9.4.x (System access) |
| NIST CSF | PR.AC-1, PR.AC-3, PR.AC-7 |
| CIS Controls | Control 5 (Accounts), Control 6 (Access management) |
| PCI-DSS | Req 7, Req 8 |
| SOC 2 | CC6.1, CC6.2, CC6.3 |
