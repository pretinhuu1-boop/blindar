---
name: load-curve
category: scalability
module: 13
priority: P2
lead: sre-lead
authority: validate
description: |
  A CURVA de escala em vez de um ponto contra SLO. Sobe uma rampa de
  concorrencia e devolve p50/p95/p99 por nivel + o joelho de saturacao. Verde
  num ponto nao diz onde o sistema degrada; a curva diz.
---

# load-curve

## O que muda em relacao ao `load-test.sh`

`scripts/load-test.sh` dispara N requisicoes numa concorrencia so e compara com
o SLO. Responde "passou neste ponto?".

Este agente responde outra pergunta: **onde comeca a degradar?**

Um sistema que passa folgado em 20 concorrentes e satura em 60 recebe verde do
gate de um ponto. O incidente acontece no primeiro pico de 80.

## O joelho

O joelho e o primeiro nivel da rampa em que:

- o erro% passa de `BLINDAR_LOAD_SLO_ERR_PCT` (1%), **ou**
- o p95 chega a `BLINDAR_LOAD_DEGRADE_X` (4x) do p95 do nivel base.

Reprova quando o joelho fica **abaixo** de `BLINDAR_LOAD_KNEE_MIN` (50). Nao
reprova por um ponto estourar: reprova por a curva virar cedo demais.

## Ausencia de joelho nao e ausencia de limite

Se a rampa termina sem joelho mas o teto testado esta abaixo do minimo alvo, o
check emite `med`: nao ha joelho **porque nao se testou ate la**. Registrar isso
e a diferenca entre "escala ate 100" e "nao sei o que acontece acima de 25".

## Nivel sem amostra e descartado, nunca contado como zero

Um nivel que nao coletou nenhuma amostra sai da curva com `measured: false`. Se
ele entrasse com p95 = 0, o melhor numero possivel viria de nenhuma medicao - e
a curva inteira mentiria para baixo.
