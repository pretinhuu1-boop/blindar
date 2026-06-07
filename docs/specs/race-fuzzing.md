# Spec: Race-fuzzing agent (item #4 do ROADMAP)

> Fuzz dirigido a races — vai além do adversarial review (que é
> análise) pra testes ativos de concorrência.

## Problema

Adversarial review (Fase 4) lens `races` **analisa** código procurando
TOCTOU, locks faltando, etc. Mas análise estática não pega:
- Race que só dispara em produção sob carga
- Interação entre 2 daemons que parece OK isoladamente
- Microsegundos entre check e act que humano não consegue ver no código

## Solução

Agente `race-fuzzing` que **roda harness** contra binário/serviço:

```
1. Identifica endpoints/handlers candidatos a race
   (qualquer que altera estado compartilhado)
2. Gera fuzz com N=100 requests concorrentes ao MESMO endpoint
   com payload variado mas equivalente
3. Verifica:
   - Estado final consistente? (saldo correto?)
   - Constraint violado? (DB rejeita corretamente?)
   - Resposta correta pra cada cliente?
4. Repete com N escalonando: 10, 100, 1000
5. Se algum nível quebra invariante: bug real
```

## Ferramentas

| Tipo | Ferramenta |
|---|---|
| HTTP concurrent | `hey`, `vegeta`, custom k6 script |
| DB race | `pg_isolation` test fixtures |
| Go race | `go test -race` (built-in) |
| Rust race | `loom` (test framework) |
| Python | `pytest-asyncio` + custom orchestrator |

## Cenários típicos

```python
# scripts/race_fuzz.py (exemplo)
import asyncio
import httpx

async def fuzz_double_spend():
    """Tenta double-spend no mesmo wallet, 50 requests concorrentes."""
    async with httpx.AsyncClient() as client:
        wallet_id = "test_wallet_1000"
        # depositar 100
        await client.post(f"/wallets/{wallet_id}/deposit", json={"amount": 100})

        # 50 saques de 10 simultaneos (total 500, deveria falhar em 90% deles)
        responses = await asyncio.gather(*[
            client.post(f"/wallets/{wallet_id}/withdraw", json={"amount": 10})
            for _ in range(50)
        ])

        # invariante: total sacado <= 100
        success = sum(1 for r in responses if r.status_code == 200)
        assert success <= 10, f"DOUBLE-SPEND: {success} saques bem-sucedidos"
```

## Integração com pipeline

- Roda na Fase 4 (adversarial) como **lens novo** `race-active`
- Findings entram em `schemas/findings.schema.json`
- Cada race confirmado vira round na Fase 3

## Por que não implementei agora

1. **Stack-específico** — harness Python ≠ Go ≠ Rust ≠ Node.
2. **Requer staging com estado controlado** — fuzz contra prod é
   crime; fuzz contra dev local não é realista.
3. **Tempo de execução**: fuzz N=1000 pode demorar 30min+. Não cabe
   no ciclo normal de round.
4. **Risk de flaky**: race conditions são inerentemente
   probabilísticas. Test flaky = falsos positivos.

## Mapeamento de frameworks

- OWASP ASVS V11.1.6 (Business logic — race protection)
- NIST CSF PR.DS-3 (assets formally managed)

## Quando faz sentido implementar

- Projeto financeiro/contábil onde double-spend é caro
- Time já tem harness de fuzz (jepsen-style) e quer integrar
- Detectado bug de race em prod uma vez (princípio do skill: bug observado)
