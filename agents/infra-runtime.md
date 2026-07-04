---
name: infra-runtime
category: core
module: 18
priority: P0
description: |
  Guarda-chuva dos 8 checks determinísticos de infra/runtime que pegam bugs que
  quebram o boot ou geram 500 — nascidos de incidentes reais (ver
  docs/CHECK-BUGS-AUDIT.md e o retrospecto). Pareiam com o smoke-runtime.
---

# Agent: infra-runtime (8 checks determinísticos)

## Missão

O smoke prova que a app sobe; estes 8 checks pegam, de forma barata e estática,
as causas mais comuns de "não sobe / 500", cada uma tirada de um incidente real.
Todos determinísticos, com par de fixture verificado no gate de self-test, e
todos self-skip quando o arquivo-alvo não existe.

| Check | Pega | Sev |
|---|---|---|
| `deps-sync` | Dockerfile instalando deps em lista fixa (dessincroniza do manifesto → ModuleNotFoundError) | high |
| `worker-jobs` | Worker com `functions=[]` / `new Worker()` sem processador (não processa nada) | high |
| `datetime-tz` | `datetime.utcnow()` naive / `DateTime` sem `timezone=True` | high/med |
| `entrypoint-cmd` | entrypoint sem `exec "$@"` (não honra o CMD, PID 1 errado) | high |
| `alembic-health` | `target_metadata=None`, falta `script.py.mako`, env.py não importa models | high/med |
| `notnull-no-default` | Coluna `NOT NULL` sem default (INSERT 500 se o code não setar) | med |
| `ratelimit-response` | slowapi `@limiter.limit` sem `response: Response` (500 em runtime) | high |
| `infra-windows` | `.bat` com parênteses no echo / sintaxe bash em `.bat` | med |

## Procedimento

Rodam no módulo 18 (junto do smoke). Cada um é `check-<nome>.sh` determinístico.
Reportam em `.blindar/results/check-<nome>.json`.

## Processo (incidente → check)

Cada um destes nasceu de um bug que passou pelos checks estáticos e só apareceu
rodando. É o pipeline `docs/INCIDENT-TO-CHECK.md`: bug real → check + par de
fixture → entra no gate. Todo incidente novo vira mais um check aqui.

## Anti-padrões

- ❌ Tratar como opcional — são baratos e pegam boot-quebrado.
- ❌ Adicionar um check sem par de fixture (fere o gate de self-test).
