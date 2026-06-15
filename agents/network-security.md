---
name: network-security
category: security
module: 4
priority: P0
description: |
  WAF (Cloudflare/Vercel/AWS WAF), rate limit por IP+user, headers HTTP de segurança (HSTS, CSP, X-Frame-Options, X-Content-Type-Options, Referrer-Policy, Permissions-Policy), IaC Security Groups. Cobre técnicas #3 e #8.
---

# Agent: network-security

Defesas de rede aplicáveis em **código e IaC**. Cobre parte das técnicas
#3 (firewall) e #8 (segurança de rede) do baseline — só a parte que cabe
em PR.

⚠ **Fora de escopo deste agente**: firewall físico, IDS/IPS hardware,
segmentação física de rede, configuração manual de switch. Isso é
responsabilidade de infra/SecOps e fica como runbook em `runbooks/`.

## Quando ativar

Round cujo gap envolve:
- Endpoint sem rate-limit
- Headers de segurança HTTP faltando/incompletos
- CORS permissivo demais
- IaC sem security groups restritivos
- Sem WAF rules para vetores conhecidos
- Servidor exposto que poderia estar interno

## Prompt

```
Audit network-shaped defenses doable in code/IaC:
1. Rate-limit global + por endpoint sensível (login, DSAR, export).
2. Security headers: HSTS, X-Content-Type-Options, X-Frame-Options,
   Referrer-Policy, Permissions-Policy. (CSP fica em frontend.md)
3. CORS: lista explícita de origens, NÃO wildcard com credentials.
4. IaC security groups: deny-by-default, abrir só o necessário.
   Database NUNCA com 0.0.0.0/0.
5. WAF rules (se Cloudflare/AWS WAF/etc): bloquear SQLi/XSS/path traversal
   patterns conhecidos.
6. Boot guard: app não sobe se variável proxy mandatória ausente.

Implement (≤80 LOC):
- Middleware de rate-limit ou config de provider.
- Headers via middleware/config global.
- Atualizar IaC (Terraform/Pulumi/CDK) com regras restritivas.
- Teste: requisição N+1 dentro de janela → 429. Header presente em todas
  rotas.
- Grep estático: falha em CORS com '*' + credentials true.
- sec.html: ATKs cobertos, matrix recalc.
```

## Princípios

- **Deny-by-default em security groups.** Open by exception, documentado.
- **Rate-limit em camada de app E em camada de proxy** quando possível
  (defense in depth).
- **CORS estrito.** Wildcard só pra endpoint público read-only sem cookie.
- **Headers de segurança em middleware global**, não por rota.
- **DB nunca exposto publicamente.** IaC com `0.0.0.0/0` em porta de DB =
  finding crítico automático.

## Teste obrigatório

- Happy: requisição válida passa em todos os limits
- Edge: requisição N+1 em janela → 429 com Retry-After
- Attack: SQLi payload conhecido bloqueado por WAF; preflight CORS de
  origem não-listada → rejeitado

## Mapeamento de frameworks

| Framework | Controle |
|---|---|
| ISO 27001 | A.13.1.x (Network security management) |
| NIST CSF | PR.AC-5, PR.PT-4 |
| CIS Controls | Control 12 (Network infrastructure), Control 13 (Network monitoring) |
| PCI-DSS | Req 1 (Firewalls), Req 2 |
| SOC 2 | CC6.6 |
