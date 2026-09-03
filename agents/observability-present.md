---
name: observability-present
category: ops
module: 6
priority: P0
lead: sre-lead
authority: implement
description: |
  Métrica exposta e alerta configurado — a pergunta que o /healthz não responde: quem é paginado quando cai? Complementa o observability (logger, health, tracing) com o elo que costuma faltar: alguém sendo acordado.
---

# Agent: observability-present

O `/healthz` responde a uma pergunta só — "o processo está de pé?" — e nenhuma
outra. Ele não diz que a latência triplicou, que a fila cresce há quarenta
minutos, que a taxa de erro passou de 0,3% para 12%. Nada disso derruba o
processo, e por isso nada disso aparece no health check.

Painel sem alerta é arqueologia: serve para entender o incidente depois, não para
descobri-lo. O modo de falha real é a organização descobrir a queda pelo cliente,
quarenta minutos depois.

Divisão com o [`observability`](observability.md): lá são logger estruturado,
health endpoints, tracing e audit trail. Aqui são duas perguntas, e só duas.

## O que o check já garante

[`check-observability-present.sh`](../templates/checks/check-observability-present.sh):

| Situação | Severidade |
|---|---|
| Sem métrica **e** sem alerta | **high** |
| Métrica + log estruturado, sem alerta | **med** |
| Métrica exposta sem nenhum alerta | **med** |
| Alerta sem métrica (só o que já quebrou dispara) | **med** |

Aceita como métrica: `prom-client`, `prometheus_client`, OpenTelemetry,
Micrometer, `/metrics`, StatsD, ou config de coletor versionada. Aceita como
alerta: Alertmanager, regras `*.rules.yml`, PagerDuty, Opsgenie, Sentry,
Bugsnag, Rollbar, política de notificação do Grafana.

Auto-skip em projeto sem processo de longa duração.

## O mínimo que vale a pena alertar

Três sinais cobrem a maior parte dos incidentes reais, e nenhum deles é
"CPU alta":

1. **Taxa de erro** por endpoint — a regressão aparece aqui antes de qualquer
   outro lugar.
2. **Latência p95** (não a média: a média esconde a cauda, e é a cauda que o
   usuário sente).
3. **Profundidade de fila / atraso do consumidor** — cresce em silêncio até
   virar queda.

Cada um precisa de destinatário nomeado. Alerta sem dono é ruído que alguém
silencia na terceira semana.

## O que só se prova com o sistema no ar

| Verificar | Como |
|---|---|
| O alerta **dispara** | provoque a condição em homologação e veja se chega |
| O alerta **chega a alguém** | canal certo, fora do horário comercial, com quem está de plantão |
| O alerta é **acionável** | quem recebe sabe o que fazer, ou é só um susto |
| Não há fadiga de alerta | alerta que dispara toda semana e ninguém olha já morreu |
