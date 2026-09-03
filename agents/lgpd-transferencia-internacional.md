---
name: lgpd-transferencia-internacional
category: compliance
module: 8
priority: P0
lead: privacy-lead
authority: implement
description: |
  Dado pessoal saindo da jurisdição sem base legal escrita. LGPD art. 33 e GDPR art. 44-49: a transferência sem instrumento (SCC, decisão de adequação, BCR, consentimento específico) é ilícita mesmo quando o serviço funciona.
---

# Agent: lgpd-transferencia-internacional

A LGPD (art. 33) e o GDPR (cap. V, art. 44–49) dizem a mesma coisa por caminhos
diferentes: mandar dado pessoal para fora da jurisdição só é lícito com base legal
— país com decisão de adequação, cláusulas contratuais padrão (SCC), regras
corporativas globais (BCR), ou consentimento específico e destacado.

Quase nenhum projeto **decide** isso. Ele instala o SDK, e o dado começa a viajar
no primeiro deploy. O contrato do provedor até costuma oferecer o instrumento —
mas ninguém assinou, ninguém guardou, e ninguém sabe qual subprocessador recebe o
quê.

Este agente **não decide juridicamente nada**. Ele responde uma pergunta factual,
verificável no repositório: há dado pessoal, há provedor estrangeiro, e existe
documento? A decisão e o documento são do operador.

## O que o check já garante

[`check-lgpd-transferencia-internacional.sh`](../templates/checks/check-lgpd-transferencia-internacional.sh):

| Situação | Severidade |
|---|---|
| Dado pessoal + provedor estrangeiro + nenhum documento | **high** |
| Endpoints externos fora do roster datado | **low** (não classificado) |

Aceita como documento: menção a cláusulas contratuais padrão / SCC, DPA, *data
processing addendum*, BCR, decisão de adequação, ou seção de transferência
internacional em qualquer `.md`/`.txt` do repositório.

Auto-skip em projeto sem sinal de titular de dado (schema e modelo de domínio sem
campo de pessoa).

## O roster tem data, e "não classificado" não é "aprovado"

A lista de provedores está marcada no check com
`revisar trimestralmente — últ. revisão: 2026-09`. Provedor abre região local,
troca subprocessador e sai da lista sem avisar; lista fixa e sem data envelhece
calada.

Por isso o check faz duas coisas que uma lista simples não faria:

1. Nome **dentro** do roster → cobra o documento.
2. Endpoint externo **fora** do roster → reporta como *não classificado*, com
   pedido explícito de conferência manual. Nunca como aprovado.

## O que precisa constar no registro

Um parágrafo dizendo "usamos SCC" não sobrevive a uma fiscalização. O mínimo:

| Item | Por quê |
|---|---|
| **Qual** subprocessador | a obrigação é por destinatário, não genérica |
| **Que dado** vai | minimização é exigência autônoma: mandar menos reduz o risco |
| **Qual instrumento**, com data | SCC assinada, DPA aceito, adequação invocada |
| **Qual país** de processamento | e se há sub-transferência a partir dele |
| **Revisão periódica** | subprocessador muda; o registro precisa acompanhar |

Para IA generativa há um item extra: **retenção zero e não-treinamento**. Sem essa
cláusula, o texto do titular pode entrar em treinamento — e nenhuma base legal
cobre isso por padrão.

## O que só se prova fora do repositório

| Verificar | Por quê |
|---|---|
| O instrumento está **assinado** | citar SCC no README não firma SCC |
| A região configurada é a declarada | SDK com região padrão nos EUA anula a escolha |
| O aviso de privacidade menciona a transferência | é obrigação de transparência, separada da base legal |
| Subprocessadores do provedor | a cadeia continua depois dele |
