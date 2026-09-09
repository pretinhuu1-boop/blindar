---
phase: 04b-assumption-probe
title: Sonda de premissa — medir o achado antes de construir sobre ele
duration_estimate: ~5 min por achado
output: .blindar/assumptions.json
runs_after: 04-rounds-loop.md
runs_before: 05-adversarial-review.md
---

# Fase 04b — Sonda de premissa

Até a v0.78 o pipeline ia do achado direto para a correção. O
`05-adversarial-review` questiona a **correção**; o `product-critic` questiona a
premissa do **produto**. Ninguém questionava a premissa do **achado**.

## Os dois casos que criaram esta fase

Numa única sessão, medindo antes de construir:

| Achado escrito | O que a medição mostrou |
|---|---|
| "a sessão vive em memória, não escala" | era DB-backed — já escalava |
| "`TRUST_PROXY /16` é um furo" | já estava mitigado em produção |

Os dois estavam escritos, plausíveis e errados. Corrigi-los teria produzido
código que precisa ser mantido para sempre, resolvendo um problema que não
existia.

## O custo que esta fase evita

Não é o bug que ficou. É o trabalho inteiro que não precisava existir — e que
entra no build, na revisão, no teste e na manutenção de todo mundo, para sempre.

Achado plausível é barato de produzir e caro de construir. Essa assimetria é o
argumento inteiro para medir antes.

## O procedimento

Para cada achado `crit` ou `high` que vai virar correção, antes de escrever
qualquer linha:

1. **Escreva a premissa em uma frase.** "Este achado só é verdade se ___."
2. **Pergunte: qual observação faria isto ser falso?**
3. **Faça essa observação.** Um `SELECT`, um `curl`, um `docker exec`, um log.
   Costuma custar minutos.
4. **Registre** em `.blindar/assumptions.json`.

```json
{ "schema": "blindar/assumptions@v1",
  "assumptions": [
    { "finding_id": "check-horizontal-scale:1",
      "premise": "a sessao vive em memoria do processo",
      "measured_how": "SELECT count(*) FROM sessions apos restart do container",
      "result": "refuted",
      "at": "2026-08-30T12:00:00Z" } ] }
```

`result` aceita `confirmed`, `refuted` e `unmeasured`.

## O que fazer com cada resultado

| `result` | Ação |
|---|---|
| `confirmed` | siga para a correção — agora sobre chão medido |
| `refuted` | **arquive o achado.** Registre a medição no `decision-log`: ela é mais valiosa que a correção teria sido |
| `unmeasured` | ou meça, ou aceite explicitamente que está construindo no escuro |

`unmeasured` não é neutro. Ausência de medição não é confirmação — a mesma
regra do `NOT VERIFIED` no gate, aplicada um nível acima, à decisão de
construir.

## O gate

[`check-assumption-probe.sh`](../templates/checks/check-assumption-probe.sh)
cruza `.blindar/assumptions.json` com `.blindar/fixes.json` pelo `finding_id`:

| Situação | Severidade |
|---|---|
| Correção sobre premissa `refuted` | `crit` |
| Correção sem premissa registrada | `high` |
| Premissa `unmeasured` | `high` |
| `confirmed` sem `measured_how` | `med` |

Alimenta o gate `DOCUMENTATION`, ao lado do `decision-log` e do
`report-integrity`: os três são sobre o registro do **porquê**.

## Anti-padrões

- Registrar `confirmed` sem `measured_how`. Confirmação sem método não é
  reproduzível nem auditável — é opinião com carimbo.
- Medir depois de implementar. A medição que chega depois da obra não evita
  custo nenhum; ela só documenta o desperdício.
- Tratar `refuted` como derrota. Um achado refutado por medição é o resultado
  mais barato do pipeline inteiro.
