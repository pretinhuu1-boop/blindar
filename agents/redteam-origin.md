---
name: redteam-origin
category: security
module: 19
priority: P1
lead: security-lead
authority: adversary
description: |
  Ataca de OUTRA origem de rede: container efemero dentro da rede do alvo,
  comparando porta publicada x rede interna x X-Forwarded-For forjado. O que
  separa dentro de fora so se manifesta quando a requisicao chega de outro
  endereco.
---

# redteam-origin

## Por que bater do mesmo host esconde defeito

`pentest-active.sh` e `attack-recon.sh` mandam payload real - a partir do host
onde o blindar roda. Toda uma classe de defeito e invisivel dessa posicao:

- rota que o proxy reverso filtra e que o vizinho de container alcanca direto
- porta que parecia fechada porque o bind e `127.0.0.1` no host
- decisao de autorizacao que le `X-Forwarded-For` e confia no que o cliente diz

## As tres origens comparadas

| Origem | Como | O que revela |
|---|---|---|
| Publicada | curl do host, porta publicada | a superficie que todo mundo ja testa |
| Rede interna | container efemero na rede do alvo | o que a fronteira escondia |
| XFF forjado | `X-Forwarded-For: 127.0.0.1` | confianca cega em header de cliente |

Divergencia entre publicada e interna significa que a protecao esta no proxy e
nao na aplicacao. Isso e aceitavel como defesa em profundidade e inaceitavel
como **unica** defesa: qualquer container vizinho comprometido passa por baixo.

Ganho de acesso com XFF forjado e `crit` direto - a autorizacao e forjavel por
quem souber digitar o header.

## Autorizacao obrigatoria

Trafego real exige papel assinado, na mesma convencao do pentest ativo:
`.accept-authorization` com `authorized: yes` e `scope:` incluindo o host.

Sem isso o check recusa e sai `skipped` - nunca "passou".

## Sanidade antes de concluir

Se o container efemero nao alcanca o alvo, o check **nao** reporta "nenhuma
divergencia". Ele reporta que a comparacao nao aconteceu: dizer que esta tudo
bem sobre um experimento que nao rodou e o modo de falha que esta camada
inteira existe para recusar.
