---
name: resource-hints
category: performance
module: 10
priority: P2
lead: frontend-lead
authority: implement
description: |
  preconnect/preload para origem de terceiro crítica. Cada origem custa DNS + TCP + TLS antes de qualquer download — 300 a 600ms em 4G, em série, começando só quando o parser encontra a referência.
---

# Agent: resource-hints

Cada origem de terceiro na página custa, **antes de qualquer download**, uma
resolução de DNS, um handshake TCP e um handshake TLS. Em 4G isso é 300–600ms por
origem, em série — e o navegador só começa essa fila quando encontra a referência,
no meio do parsing, tarde demais.

`preconnect` antecipa o handshake para o começo do documento. `preload` antecipa
o download do que é crítico. Um `<link rel="preconnect">` de uma linha costuma
valer mais que qualquer minificação: **não reduz bytes, remove espera**.

Onde mais dói: fonte (bloqueia o texto), script de pagamento (bloqueia o
checkout), tag de analytics carregada no `head`.

## O que o check já garante

[`check-resource-hints.sh`](../templates/checks/check-resource-hints.sh):

| Situação | Severidade |
|---|---|
| Origem de terceiro crítica sem `preconnect`/`preload`/`dns-prefetch` | **low** por origem |

Origens consideradas críticas: Google Fonts (`googleapis` e `gstatic`), Typekit,
Stripe, Mercado Pago, PagSeguro, Google Tag Manager, Google Analytics, jsDelivr,
unpkg, cdnjs, Vimeo, YouTube.

Quando não há nenhuma origem de terceiro nas páginas servidas, o check passa
dizendo que **não há handshake a antecipar** — que é diferente de não ter
verificado.

Auto-skip em projeto sem documento HTML nem componente de `head`.

## As regras que evitam piorar

- **`preconnect` só no que é usado logo.** Cada um consome uma conexão; seis
  `preconnect` especulativos disputam banda com o que importa. Três é um número
  saudável.
- **`crossorigin` obrigatório para fonte.** `<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>`
  — sem o atributo, o navegador abre uma segunda conexão e o hint não serve para
  nada.
- **`preload` exige `as`.** Sem ele o recurso é baixado duas vezes, e o console
  avisa.
- **`dns-prefetch` como reserva** para navegador antigo, e para origem provável
  mas não certa.
- **A melhor otimização é remover a origem.** Fonte auto-hospedada não precisa de
  `preconnect`, e ainda elimina um ponto de falha de terceiro.

## O que só se prova medindo

| Verificar | Como |
|---|---|
| O hint encurtou o caminho crítico | waterfall antes e depois, com throttling de 4G |
| Não há `preconnect` desperdiçado | conexão aberta e não usada aparece como ociosa |
| A fonte não bloqueia o texto | `font-display: swap` continua sendo necessário |
