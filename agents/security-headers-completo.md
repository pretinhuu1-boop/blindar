---
name: security-headers-completo
category: security
module: 4
priority: P1
lead: security-lead
authority: implement
description: |
  A segunda metade dos cabeçalhos: Permissions-Policy e isolamento de origem (COOP/COEP/CORP), lidos da resposta HTTP real quando há alvo e da configuração sempre. Estende o headers-security, que cobre CSP/HSTS/XFO/Referrer.
---

# Agent: security-headers-completo

O `check-headers-security` cobre os quatro clássicos: CSP, HSTS,
X-Frame-Options, Referrer-Policy. Este cobre o que quase ninguém configura e que
fecha buracos reais.

**`Permissions-Policy`** desliga câmera, microfone, geolocalização, pagamento e
sensores que a aplicação não usa. Sem ele, qualquer script que entre na página —
tag de analytics, dependência comprometida, widget de terceiro — pode pedir esses
acessos **em nome do seu domínio**, com a sua reputação no diálogo de permissão.

**COOP / COEP / CORP** isolam o contexto de navegação. Sem COOP, uma janela
aberta a partir do seu site mantém referência ao `window` dele. Sem
cross-origin isolation não há defesa de processo contra ataque de canal lateral
tipo Spectre — e é ela que habilita `SharedArrayBuffer` e medição de tempo
precisa quando você precisar deles.

## Duas fontes de verdade, nesta ordem

1. **A resposta HTTP real**, quando há alvo (`--url=` ou `BLINDAR_TARGET_URL`).
2. **A configuração no repositório**, sempre.

A ordem importa porque **config certa com proxy sobrescrevendo é o caso comum**.
O `helmet` está lá, o nginx não repassa, e o que chega ao navegador é o que
vale. Quando o alvo responde, o check também confere os quatro clássicos —
porque ali a pergunta deixa de ser "está declarado?" e passa a ser "chegou?".

Sem alvo, o `missing_tool` sai preenchido com `alvo-http-ausente`: aprovado com
buraco não pode ficar indistinguível de aprovado com cobertura completa.

## O que o check já garante

[`check-security-headers-completo.sh`](../templates/checks/check-security-headers-completo.sh):

| Cabeçalho ausente | Severidade |
|---|---|
| `Permissions-Policy` | **med** |
| `Cross-Origin-Opener-Policy` | **low** |
| `Cross-Origin-Embedder-Policy` | **low** |
| `Cross-Origin-Resource-Policy` | **low** |
| CSP / HSTS (só com resposta real) | **high** |
| X-Frame-Options (só com resposta real) | **med** |

Auto-skip em projeto sem servidor HTTP.

## O ponto de partida razoável

```
Permissions-Policy: camera=(), microphone=(), geolocation=(), payment=(), usb=(), interest-cohort=()
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Resource-Policy: same-site
```

`Cross-Origin-Embedder-Policy: require-corp` é o mais invasivo dos três: quebra
embed de terceiro que não envia CORP. Ligue com `report-only` antes.

## O que só se prova com o site no ar

| Verificar | Por quê |
|---|---|
| O cabeçalho **chega** | CDN, WAF e proxy reverso reescrevem e removem |
| Chega em **todas** as rotas | middleware aplicado só numa árvore de rotas é o erro comum |
| A CSP não está em `report-only` esquecido | relatório sem enforcement não bloqueia nada |
| Embed de terceiro sobrevive ao COEP | pagamento e vídeo costumam quebrar |
