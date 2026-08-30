---
name: negative-control
category: testing
module: 11
priority: P1
lead: qa-lead
authority: gate
description: |
  Gate de correcao: toda correcao precisa de controle negativo EXECUTADO -
  quebrei o codigo de proposito e o teste caiu. Score agregado de mutation
  testing e compativel com o teste da correcao de hoje nao proteger nada.
---

# negative-control

## Por que score agregado nao basta

`testing-strategy.md` prescreve mutation testing com score > 80%. E uma media -
e uma media de 85% convive perfeitamente com o teste da correcao de hoje nao
protegendo absolutamente nada, desde que os outros duzentos protejam.

O controle negativo e **individual e local**: depois de corrigir, quebre o
codigo de proposito e confirme que o teste cai. Se ele nao cai, o teste nao
protege a correcao; ele so passa perto dela.

## O registro

`.blindar/negative-controls.json`, cruzado com `.blindar/fixes.json` pelo mesmo
`finding_id` (`<agent>:<indice>`) que o `blindar-fix.sh` ja usa:

    { "finding_id": "check-security:0",
      "how_broken": "removi o escape em src/db/query.ts",
      "test": "tests/query.spec.ts::rejeita aspas",
      "observed": "failed",
      "at": "2026-08-30T10:00:00Z" }

## Severidades

| Situacao | Severidade |
|---|---|
| Correcao sem controle | `high` |
| `observed` diferente de `failed` | `crit` |
| Controle sem `how_broken` ou `test` | `med` |

`observed: passed` e `crit` e nao `high` porque e o pior dos casos: alguem
quebrou o codigo, o teste passou mesmo assim, e isso ficou registrado como se
fosse prova. Um verde desses e pior que a ausencia do teste - ele produz
confianca onde nao ha protecao.

## Sem registro de correcao

Se `.blindar/fixes.json` nao existe ou esta vazio, o check sai `skipped` com
`missing_tool` preenchido. O gate le isso como cobertura ausente, nao como
aprovacao: "ninguem registrou nada" e "esta tudo protegido" sao estados
diferentes.
