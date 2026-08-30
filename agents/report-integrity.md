---
name: report-integrity
category: reporting
module: 14
priority: P2
lead: release-lead
authority: gate
description: |
  O laudo se corrige quando a medicao o contradiz. decision-log e
  execution-report REGISTRAM; nenhum se auto-corrige. Sem isso a primeira versao
  vira fonte de verdade e a correcao nunca alcanca quem ja leu.
---

# report-integrity

## O problema

Um relatorio emitido e um artefato que circula. Quando uma medicao posterior
derruba uma afirmacao dele, existem duas coisas no mundo: a medicao nova e as
pessoas que leram a versao antiga.

Sem mecanismo de correcao, o relatorio fica mais confiavel do que a medicao que
o desmente - que e exatamente a inversao errada.

## O formato

    .blindar/report.json            versao corrente
    .blindar/report-history/*.json  versoes anteriores, uma por arquivo

    { "schema": "blindar/report@v1",
      "version": 2,
      "supersedes": 1,
      "claims": [ { "agent": "check-horizontal-scale", "status": "passed" } ],
      "corrections": [
        { "agent": "check-horizontal-scale", "was": "failed", "now": "passed",
          "why": "a medicao mostrou sessao DB-backed; a v1 estava errada" } ] }

## A regra

Toda afirmacao que **mudou de status** entre a versao anterior e a atual precisa
aparecer em `corrections`, com o motivo.

Status que vira o contrario em silencio e o laudo se editando sem dizer que se
editou. Quem leu a v1 continua com a afirmacao errada, e nada na v2 avisa que
ela caiu.

## Severidades

| Situacao | Severidade |
|---|---|
| Afirmacao mudou sem entrada em `corrections` | `high` |
| `version` ausente ou nao numerico | `high` |
| `supersedes` nao aponta para a versao anterior | `med` |
| Correcao sem `why` | `med` |

## Primeira versao

Sem historico, nao ha contradicao possivel: o check passa e diz isso
explicitamente. A disciplina so comeca a valer quando existe uma v1 que alguem
pode ter lido.
