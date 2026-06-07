# Fase 4 — Adversarial review

**Duração**: ~10 min

**Cadência**: a cada 10 rounds completos da Fase 3.

## Objetivo

Quatro lenses paralelas tentando **refutar** o trabalho feito. Confirmados
viram novos rounds na fila.

## Execução

```javascript
const LENSES = [
  { key: 'security',   prompt: 'auth bypass, header injection, ownership bypass, info disclosure...' },
  { key: 'races',      prompt: 'TOCTOU, missing locks, atomic writes, lock ordering...' },
  { key: 'failmodes',  prompt: 'disk full, key rotation, breaker permanent, dead code, fail-open...' },
  { key: 'regression', prompt: 'existing flows still work, backward-compat, dead defenses...' },
]

phase('Review')
const findings = await pipeline(
  LENSES,
  d => agent(
    d.prompt + ' Files mexidos: <last 10 PRs>',
    { schema: FINDINGS_SCHEMA, phase: 'Review' }
  ),
  (review, d) => parallel((review.findings || []).map((f, i) => () =>
    agent(
      `Adversarially verify: ${f.title}. Default refuted=true if uncertain.`,
      { schema: VERDICT_SCHEMA, phase: 'Verify' }
    ).then(v => ({ ...f, lens: d.key, verdict: v }))
  ))
)

const confirmed = findings.flat().filter(f => f?.verdict?.isReal)
```

## Lenses

| Lens | Procura |
|---|---|
| `security` | auth bypass, header injection, ownership bypass, info disclosure |
| `races` | TOCTOU, locks faltando, escritas não-atômicas, lock ordering |
| `failmodes` | disk full, key rotation, breaker permanente, dead code, fail-open |
| `regression` | flows quebrados, backward-compat, defesas mortas |

## Verify

Cada finding é validado por um agente que tenta **refutar** com
`refuted=true` por padrão (princípio: confirmar custa esforço, refutar é
default seguro).

Sobrevive ao verify → é "real" → entra na fila como novo round.

## Detalhes

Ver [`agents/adversarial-reviewer.md`](../agents/adversarial-reviewer.md).
