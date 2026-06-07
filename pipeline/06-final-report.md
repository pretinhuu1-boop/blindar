# Fase 6 — Relatório final

**Duração**: ~2 min

## Objetivo

PR final com sumário do hardening completo.

## PR

Branch: `sec/final-report`
Mensagem: `docs(blindar): final report`

## Conteúdo do PR

- N rounds completados, M PRs mergeados, K testes adicionados
- `sec.html` v∞ com matrix final
- Bundle size / pytest count / CI duration (antes vs depois)
- Runbooks criados em `docs/`
- Riscos aceitos do `.accept-risk.md`

## Termination

Para automaticamente quando todas as condições são verdadeiras:

- [ ] 0 confirmed crit no último adversarial
- [ ] ≤ 2 confirmed high (acknowledged em `.accept-risk.md`)
- [ ] Categorias críticas (web_api, auth, supply_chain, infra, compliance,
      resilience) ≥ 80% covered+partial
- [ ] 3 runbooks: `incident-response.md`, `key-rotation.md`,
      `supply-chain.md`
- [ ] CI verde por 3 PRs consecutivos
- [ ] Production checklist (Fase 5): todos os `bloqueia: sim` ✓
