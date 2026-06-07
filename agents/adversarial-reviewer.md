# agent: adversarial-reviewer

Não é um agente único — é o **workflow** descrito em
[`pipeline/04-adversarial-review.md`](../pipeline/04-adversarial-review.md).

## Estrutura

4 lenses paralelas + verify:

| Lens | Procura |
|---|---|
| `security` | auth bypass, header injection, ownership bypass, info disclosure |
| `races` | TOCTOU, locks faltando, escritas não-atômicas, lock ordering |
| `failmodes` | disk full, key rotation, breaker permanente, dead code, fail-open |
| `regression` | flows quebrados, backward-compat, defesas mortas |

Cada lens recebe contexto dos **últimos 10 PRs mergeados** e retorna
`findings`.

## Verify (default refute)

Cada finding entra num agente verificador com instrução:

> Adversarially verify: {title}. **Default refuted=true if uncertain.**

Princípio: refutar é o default seguro. Confirmar custa esforço.

Sobrevive ao verify (`isReal: true`) → entra na fila como novo round na
Fase 3.

## Cadência

A cada 10 rounds completos da Fase 3. Não roda no meio de um round.

## Output esperado

```json
{
  "findings_raw": 17,
  "findings_confirmed": 4,
  "by_lens": { "security": 2, "races": 1, "failmodes": 1, "regression": 0 }
}
```

Confirmed → fila de rounds. Refuted → log + descarte.
