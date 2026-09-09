---
name: failure-ux
category: runtime
module: 18
priority: P1
lead: runtime-lead
authority: validate
description: |
  O que o CLIENTE recebe quando quebra. Provoca rota inexistente, corpo
  malformado e falha de dependencia contra o alvo vivo, e le status, corpo e
  Content-Type. Resiliencia medida da estrutura nao e a mesma coisa que a
  mensagem que chega na tela.
---

# failure-ux

## A distancia entre "tem try/catch" e "o erro faz sentido"

Os checks de resiliencia do blindar medem estrutura. Este mede a **resposta**.

| Provocacao | Resposta correta | O que o defeito parece |
|---|---|---|
| Rota inexistente | 404 | 500 - todo bot varrendo URL vira alerta de 5xx |
| JSON malformado | 400 | 500 - cliente nao distingue o proprio bug de incidente |
| Erro em endpoint de API | `application/json` | `text/html` - front quebra em `JSON.parse` |
| Dependencia congelada | 503 | 401 - o banco tossiu e o usuario foi deslogado |

## O pior desfecho da tabela

`401` sob falha de infraestrutura. O produto diz ao usuario que ele nao tem
permissao, quando o problema e o banco. Ele vai tentar logar de novo e falhar de
novo, e o suporte vai receber um chamado sobre autenticacao enquanto o incidente
real e de infraestrutura.

Isso nao aparece em nenhum check estatico: o codigo de tratamento existe, esta
la, e traduz errado.

## Vazamento de rastro

Qualquer resposta que carregue `Traceback`, caminho de arquivo com linha e
coluna, `node_modules/`, `site-packages/`, `SQLSTATE` ou nome de driver e
`crit`. O atacante recebe framework, versao e estrutura de diretorios de graca,
no primeiro request malformado.

## Honestidade sobre o que nao rodou

Sem Docker ou sem dependencia amarrada ao alvo, o probe de falha de infra nao
roda - e o check registra isso como achado `low` explicito, em vez de sumir com
a lacuna. A traducao erro-de-infra para status-do-cliente fica **nao
verificada**, que e diferente de correta.
