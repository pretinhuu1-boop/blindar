---
name: environment-parity
category: data
module: 7
priority: P1
description: |
  Compara dev × test × staging × produção e reporta divergências que produzem falso-verde. O caso clássico: TEST em SQLite e PROD em PostgreSQL — a suite passa porque SQLite aceita o que o Postgres recusa. Emite ENVIRONMENT DRIFT REPORT.
---

# Agent: environment-parity

Os ambientes representam a produção, ou só se parecem com ela?

Existe porque uma suite verde num ambiente que não é o de produção **produz
confiança falsa** — e é justamente essa confiança que autoriza o deploy.

> **Caso canônico**: DEV=PostgreSQL, TEST=SQLite, PROD=PostgreSQL. A suite fica
> verde porque o SQLite aceita o que o Postgres recusa: FK não aplicada por
> default, tipos frouxos, sem `TIMESTAMPTZ` real. O bug não é detectável por
> nenhum teste — o ambiente de teste foi construído para não detectá-lo.

## Quando ativar

Sempre que houver mais de um ambiente declarado (dois ou mais `.env*`, ou
compose com override). Roda 1x no ciclo.

## O que comparar

| Dimensão | Divergência que importa |
|---|---|
| **Engine de banco** | qualquer diferença — é a mais grave |
| Versão maior da engine | planner e sintaxe mudam entre majors |
| Fila / broker | fila real em prod, execução síncrona em test = retry e DLQ nunca exercitados |
| Cache | Redis em prod, cache em memória em test = invalidação nunca testada |
| Storage | S3 em prod, disco local em test = permissão e latência nunca exercitadas |
| Runtime | versão de Node/Python/Go diferente |
| TLS / proxy | prod atrás de proxy, dev direto = header de host, IP real, cookie secure |
| Migrations | prod aplica migration, test recria schema do zero |
| Variáveis | presente em um, ausente no outro |

A pergunta de corte, em cada linha: **um bug desta dimensão seria detectável
antes da produção?** Se não, é drift que importa.

## Output — ENVIRONMENT DRIFT REPORT

```
ENVIRONMENT DRIFT REPORT
─────────────────────────────────────────────
Dimensão      DEV          TEST         PROD        Status
─────────────────────────────────────────────
DB engine     postgres:16  sqlite       postgres:16  ✗ DIVERGENTE
Fila          redis        in-memory    redis        ✗ DIVERGENTE
Cache         redis        redis        redis        ✓
Runtime       node 22      node 22      node 20      ⚠ minor
─────────────────────────────────────────────
Veredito: 2 divergências que produzem falso-verde
```

Cada divergência precisa de veredito explícito: **aceitável** (com motivo) ou
**a corrigir**. Divergência listada sem veredito é ruído.

Algumas são legítimas: storage local em dev enquanto prod usa S3 é aceitável se
a interface for a mesma e existir teste de integração contra o storage real.
Engine de banco diferente **nunca** é aceitável — não há interface comum que
cubra tipos, constraints e semântica de transação.

## Verificação determinística

[`check-environment-parity.sh`](../templates/checks/check-environment-parity.sh)
cobre o núcleo: engine divergente entre arquivos de env (**high**) e versão
maior divergente do Postgres entre composes (**med**). As demais dimensões da
tabela são avaliadas por este agente.

## Relação com outros agentes

- [`db-migration-guardian`](db-migration-guardian.md) — quando o drift de
  engine é resultado de uma migração incompleta, quem corrige é ele.
- [`smoke-runtime`](smoke-runtime.md) — prova que o ambiente sobe; este prova
  que ele é o ambiente **certo**.
- [`chaos-engineering`](chaos-engineering.md) — só faz sentido contra um
  ambiente que representa produção.

## Anti-padrões

- ❌ Aceitar SQLite em teste "porque é mais rápido". O custo aparece em
  produção, com juros.
- ❌ Comparar só o banco e declarar paridade.
- ❌ Exigir paridade absoluta — dev não precisa de réplica nem de CDN. O
  critério é o falso-verde, não a igualdade.
- ❌ Reportar divergência sem dizer se é aceitável.
- ❌ Tratar `.env.example` como o ambiente de dev real sem verificar se existe
  um `.env` local divergente.
