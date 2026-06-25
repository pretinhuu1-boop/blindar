# Agente: Race-fuzzing (ROADMAP #4 — testes ativos de concorrência)

> Vai além do adversarial review (lens `races`, que **analisa**). Este
> **roda** harness de concorrência contra o serviço/handler.
> Implementa [`docs/specs/race-fuzzing.md`](../docs/specs/race-fuzzing.md).
> Harness executável: [`scripts/race-fuzz.js`](../scripts/race-fuzz.js).

## Quando ativar

- Após lens `races` do adversarial sinalizar candidato, OU
- Sempre que `db-architect`/`business-logic` apontar check-then-act / saldo /
  estoque / idempotência.
- Opt-in via `roles: [race-fuzz]` / módulo correspondente.

## Pré-condições (PARA se faltar)

- App/serviço sobe local (modo http) — ou worker isolável (modo in-memory).
- Ambiente isolado (nunca produção com dados reais).
- Invariante claro do recurso ("saldo nunca negativo", "estoque ≥ 0").

## O que faz

1. Identifica handlers que alteram **estado compartilhado**.
2. Dispara N requests concorrentes ao MESMO recurso, **N escalonando**
   (10 → 100 → 1000).
3. Verifica o invariante a cada nível:
   - Estado final consistente? (saldo/estoque corretos?)
   - Constraint do banco respeitado? (rejeitou o excesso?)
   - Resposta correta pra cada cliente?
4. Se algum nível quebra o invariante → **race real** (round de fix).

## Cenários típicos

- **Double-spend**: depósito 100, depois 50 saques de 10 simultâneos → só 10
  podem passar; se passar mais, race.
- **Oversell de estoque**: estoque 5, 20 compras simultâneas → no máx 5.
- **Idempotência**: mesma `Idempotency-Key` em N requests → 1 efeito só.

## Fix esperado (o que o round entrega)

- **Reservation pattern** > check-then-act (`UPDATE ... WHERE stock >= ?`).
- Transação + nível de isolamento correto.
- Constraint no banco como última linha (CHECK/UNIQUE).
- Chave de idempotência persistida.

O harness valida o fix: depois do patch, todos os níveis preservam o invariante.

## Gate

- Invariante quebrado em qualquer nível → crit (não passa termination).
- Fix sem o harness reverde → não mergeia.

## Anti-padrões

- ❌ Rodar contra produção.
- ❌ Declarar "sem race" só com análise estática (este agente existe porque
  estática não pega corrida de microssegundos).
- ❌ Fix que passa N=10 mas quebra N=1000 (testar o nível alto).
