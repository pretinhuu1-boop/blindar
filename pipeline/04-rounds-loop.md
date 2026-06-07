# Fase 3 — Loop de rounds

**Duração**: até termination (ver `SKILL.md`)

## Objetivo

Fechar gaps da matrix, um por vez, cada um virando um PR mergeado.

## Para cada round

1. **Pick** — highest-severity gap do matrix
2. **Spawn** — agente especialista da categoria (ver [`agents/`](../agents/))
3. **Implement** — ≤ 80 LOC + teste real (≥ 3 asserts) + grep estático
4. **Update** — `sec.html`: ATK gap→covered, matrix recalc, version++
5. **Local check** — suite verde + type-check verde
6. **Commit** — branch `sec/<round-id>-<slug>` + template message
7. **Push + CI** — aguardar verde (sem `--no-verify`)
8. **Merge** — `gh pr merge --squash --delete-branch`
9. **Next**

A cada 10 rounds completos: **Fase 4** (adversarial review) automaticamente.

## Roster de agentes

| Categoria | Agente |
|---|---|
| Segurança aplicacional | [`agents/security.md`](../agents/security.md) |
| Performance | [`agents/performance.md`](../agents/performance.md) |
| Threads / locks / breakers | [`agents/resilience.md`](../agents/resilience.md) |
| Escalabilidade (stub) | [`agents/scalability.md`](../agents/scalability.md) |
| Compliance genérico | [`agents/compliance.md`](../agents/compliance.md) |
| LGPD / ANPD (BR) | [`agents/compliance-lgpd-br.md`](../agents/compliance-lgpd-br.md) |
| Supply chain / CI | [`agents/supply-chain.md`](../agents/supply-chain.md) |
| Frontend / CSP | [`agents/frontend.md`](../agents/frontend.md) |
| DevOps / deploy | [`agents/devops.md`](../agents/devops.md) |

## Quality gates por round

| Gate | Verificação | Bloqueia |
|---|---|---|
| Suite | pytest/vitest/etc verdes após cada round | merge |
| CI | todos jobs verde | merge |
| sec.html | commit junto com código do round | commit |
| Test real | ≥ 3 assertions cobrindo happy + edge + attack | round |
| Guard estático | grep que falha se defesa regredir | round |
| Branch | 1 PR/round, squash, branch deletada | sempre |

## Template de PR

Ver [`templates/pr-message.md`](../templates/pr-message.md).

## Anti-padrões (NUNCA)

- PR > 200 LOC ou > 5 arquivos → quebra em 2 rounds
- Implementação sem teste
- `sec.html` sem código mergeado
- Refactor durante hardening (PR próprio)
- Defesa nova quebrando teste antigo (refletir, ajustar contrato, NÃO silenciar)
- CI vermelha mergeada
- Schema `sec.html` mudando entre rounds
