---
name: smoke-runtime
category: core
module: 18
priority: P0
description: |
  Prova que a app SOBE e responde (verdade de runtime). Sobe o stack em homolog
  (mock no banco, espelho de produção — nunca dev), espera health e roda 1 fluxo
  crítico. Pega boot-quebrado e 500 de runtime que nenhum grep acha.
---

# Agent: smoke-runtime

## Missão

Este é o **maior furo histórico do blindar**: os checks estáticos diziam
"0 failures, cobertura 98%" enquanto a imagem nem bootava e havia vários 500.
`grep` nunca pega imagem-não-boota, `ModuleNotFoundError`, `slowapi` sem
`response: Response`, coluna `NOT NULL` não setada, worker com `functions=[]`.
Só rodando de pé.

Custo de não rodar: entregar "verde" um app que não sobe. É o pior falso
positivo possível — o oposto de segurança.

## Procedimento

```bash
bash ~/.claude/skills/blindar/scripts/smoke-run.sh          # sobe compose homolog
# ou, homolog remoto já de pé:
bash ~/.claude/skills/blindar/scripts/smoke-run.sh --url https://homolog.exemplo.com
```

1. **Sobe em homolog** (`docker-compose.homolog.yml` preferido, senão o base com
   `BLINDAR_ENV=homolog`). Dados **mock direto no banco**, espelho de produção.
   Se `docker compose up` falhar → finding **crit** (boot quebrado).
2. **Espera health** (`/health/ready`, `/healthz`, `/readyz`, `/health`, `/`)
   até `--timeout` (default 60s). Nunca respondeu → finding **crit**.
3. **Fluxo crítico**:
   - Se existir `.blindar/smoke-flow.sh`, roda ele (fluxo custom real, ex:
     signup→login→GET protegido). Recomendado por projeto.
   - Senão, varre os GET externos do grafo (`.blindar/graph.json`, sem params).
     Qualquer 5xx → finding **high** (500 de runtime).
4. **Derruba** os containers (`down -v`) — a menos que `--keep`.

## Homolog, nunca dev

Pareia com `check-homolog-only.sh`: o smoke recusa subir em modo dev. Simulação
= homologação idêntica ao que vai pra produção, com dados mock semeados no banco
real (não sqlite/:memory:/dev.db). Ver a regra em `check-homolog-only.sh`.

## Reusa o grafo (Fase 1)

Lê `.blindar/graph.json` pra saber a porta exposta (qual URL bater) e quais
endpoints externos varrer. Constrói o grafo se faltar. Zero re-descoberta.

## Output esperado

`.blindar/results/check-smoke-runtime.json` (status passed/failed/skipped).
Findings: boot-quebrado (crit), health-ausente (crit), 500-de-runtime (high).

## Ordem no pipeline (security-first)

Roda **depois** de implementar o que falta e **antes** do ataque — provar que
sobe é pré-requisito pra atacar. Sequência: analisar → implementar → **smoke** →
atacar → proteger → revisar.

## Anti-padrões

- ❌ Subir em dev "só pra testar" — homolog espelha produção.
- ❌ Marcar passed sem bater em nenhum endpoint.
- ❌ Deixar containers de pé (vaza recurso) — sempre teardown, exceto `--keep`.
- ❌ Semear dados por API lenta quando dá pra semear direto no banco.
