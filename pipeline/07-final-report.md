# Fase 7 — Relatório final

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

Obrigatório desde a v0.57:

- **Modo de operação usado** e a evidência que o produziu
  (`operation_mode_evidence` do config). Sem isso não há como auditar por que o
  pipeline se comportou de determinada forma.
- **Tabela dos 11 gates** com a coluna de evidência, e o veredito
  **GO / CONDITIONAL GO / NO-GO** (`.blindar/gates.json`).
- **Gates pulados por modo**, nomeados. Gate pulado em silêncio é
  indistinguível de gate aprovado.
- **Decisões arquiteturais** do ciclo (`docs/decisions.md`).
- **O que NÃO foi alterado, e por quê.** É a seção que mais falta e a que o
  próximo leitor mais precisa: sem ela, "não aparece no relatório" se confunde
  com "não existe".

## Princípio de evidência (⭐ v0.57)

Toda afirmação do relatório precisa de onde ser verificada.

| Não escreva | Escreva |
|---|---|
| "PostgreSQL está configurado" | "PostgreSQL em `docker-compose.yml:3`, usado por `src/db.ts:1`, migration `002`, runtime validado por `smoke-run.sh` (conexão vista em `pg_stat_activity`)" |
| "Autenticação segura" | "Autenticação em `src/auth.ts:14`, testada em `auth.test.ts` (3 casos), rota sem token responde 401" |
| "Backup configurado" | "Backup em `scripts/backup.sh`, restore testado em 2026-08-14, resultado: 12.480 linhas conferidas" |

A regra é verificável na fonte por
[`check-evidence.sh`](../templates/checks/check-evidence.sh): todo achado
`crit`/`high` precisa de `file` preenchido, e todo gate de `evidence`.

Achado de **runtime** é a exceção — não tem arquivo por natureza. "Erro de 100%
acima do SLO de 5% com 10 concorrentes" é evidência completa, e para esses
agentes o gate exige a medição na mensagem em vez da localização.

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
