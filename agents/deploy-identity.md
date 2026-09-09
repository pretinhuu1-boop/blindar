---
name: deploy-identity
category: deployment
module: 18
priority: P0
lead: release-lead
authority: gate
description: |
  Compara o hash do artefato NO AR com o commit auditado. Sem isso, auditar o
  codigo e subir outra imagem produz um verde honesto sobre uma coisa que
  ninguem esta usando. Foi assim que 17 checks passaram contra a imagem errada.
---

# deploy-identity

## A licao que originou este agente

Dezessete checks passaram. O relatorio saiu verde. A imagem que estava servindo
trafego era outra.

Nenhum dos checks estava errado: todos mediram corretamente o repositorio. O
defeito era a premissa silenciosa de que o repositorio e o artefato no ar sao a
mesma coisa.

## O que o check exige

O health (ou o endpoint passado em `--health`) precisa declarar a identidade do
build. Aceita:

- chave no corpo JSON: `commit`, `commit_sha`, `sha`, `git_sha`, `revision`,
  `rev`, `build`, `build_sha`, `version` - valor de 7 a 40 hex
- header dedicado: `X-Commit-Sha`, `X-Build-Sha`, `X-Revision`

A comparacao e por prefixo, entao 7, 8, 12 ou 40 caracteres funcionam igual.

## Tres desfechos

| Situacao | Severidade | Por que |
|---|---|---|
| Bate | - | a auditoria e sobre o que esta rodando |
| Diverge | `crit` | todo veredito da rodada e sobre outro artefato |
| Nao declara | `high` | impossivel provar qualquer relacao entre os dois |

"Nao declara" e `high` de proposito. Um verde sobre artefato anonimo tem
exatamente o mesmo valor probatorio de nenhum verde.

## Arvore suja

Se ha alteracao nao commitada, o check emite `med` mesmo com o SHA batendo: o
que roda e o commit, e o que acabou de ser auditado e o working tree. Sao
parecidos, nao iguais - e a diferenca aparece justo quando alguem "so ajustou
uma coisinha antes de rodar o blindar".

## Autoridade de gate

Este e um dos poucos agentes com `authority: gate`. Ele nao edita nada; ele
impede que `DEPLOYMENT` chegue a `PASS` sem a amarracao entre codigo e artefato.
