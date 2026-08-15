---
phase: 06b-release-gates
title: Release gates — 11 dimensões + veredito GO / CONDITIONAL GO / NO-GO
duration_estimate: ~1 min
output: .blindar/gates.json
runs_after: 06-production-checklist.md
runs_before: 07-final-report.md
---

# Fase 06b — Release gates

Até a v0.52, "pronto para produção" era `0 crit + ≤2 high após adversarial`.
Esse critério mede **o que os checks acharam**, não o que ficou por verificar.

Um projeto pode ter 0 crit e 0 high e mesmo assim:

- rodar SQLite enquanto a infra declara PostgreSQL,
- não ter backup que alguém já tenha restaurado,
- não ter caminho de rollback,
- ter mock no caminho crítico,
- não ter observabilidade nenhuma.

Nada disso aparece como severidade agregada. Por isso a decisão passa a ter
**11 dimensões independentes**: uma sozinha pode bloquear, e severidade baixa
em uma não compensa buraco em outra.

Executado por
[`templates/checks/check-release-gates.sh`](../templates/checks/check-release-gates.sh),
que agrega `.blindar/results/*.json` e emite `.blindar/gates.json`
(schema: [`gates.schema.json`](../schemas/gates.schema.json)).

---

## As 11 dimensões

| Gate | Pergunta que responde |
|---|---|
| `SECURITY` | dá para invadir? |
| `ARCHITECTURE` | as fronteiras se sustentam? |
| `DATABASE` | o banco está correto **e é o que a infra declara**? |
| `RUNTIME` | o que o código afirma acontece de fato quando roda? |
| `RESILIENCE` | o que acontece quando uma dependência cai? |
| `OBSERVABILITY` | se quebrar às 3h, dá para descobrir o quê? |
| `PRIVACY` | os dados pessoais têm ciclo de vida? |
| `QUALITY` | a pessoa que usa consegue usar? |
| `DEPLOYMENT` | dá para subir — e para voltar? |
| `BACKUP_RECOVERY` | o dado volta depois de perdido? |
| `DOCUMENTATION` | outra pessoa consegue operar isso? |

## Estados possíveis

| Estado | Significado | Conta como |
|---|---|---|
| `PASS` | checks rodaram, nenhum finding | — |
| `PASS WITH WARNINGS` | finding não-crit, ou check não verificado por ferramenta ausente | warning |
| `NOT VERIFIED` | **nenhum check desta dimensão executou** | warning |
| `BLOCKED` | ≥1 finding crit | bloqueio |

`NOT VERIFIED` é a distinção que mais importa. "Não rodou" e "não se aplica"
são estados diferentes, e só o operador consegue separá-los: um CLI
legitimamente não tem gate de frontend; um SaaS sem nenhum check de banco tem
um buraco, não uma isenção. Por isso `NOT VERIFIED` **nunca vira PASS
automaticamente** — é dispensado por aceite assinado, como qualquer warning.

Mesma lógica vale dentro de um gate: check que virou `skipped` por ferramenta
ausente (`missing_tool` preenchido no result) impede o `PASS`. Falta de
instrumentação não é aprovação.

## Provas positivas — dois gates exigem mais que ausência de finding

`BACKUP_RECOVERY` só chega a `PASS` com evidência de **restore**, não de
backup. Backup que ninguém restaurou é hipótese: o arquivo existe, e a primeira
tentativa real de usá-lo é durante o incidente.

`DEPLOYMENT` só chega a `PASS` com **rollback** documentado. Saber subir sem
saber voltar é metade do procedimento.

## Veredito

| Veredito | Condição |
|---|---|
| `GO` | nenhum BLOCKED, nenhum warning |
| `CONDITIONAL GO` | nenhum BLOCKED, ≥1 warning — cada um aceito em `.accept-risk.md` |
| `NO-GO` | ≥1 BLOCKED, **ou** nenhum check produziu resultado |

A segunda condição do `NO-GO` fecha o buraco mais perigoso: rodar zero checks e
receber GO porque não havia nada reprovando. Sem medição não há veredito, e
ausência de veredito nunca é aprovação — a mesma regra que o
`check-termination.sh` já aplica para `jq` ausente.

`GO` é raro por construção. Na maioria dos projetos reais o resultado honesto é
`CONDITIONAL GO` com warnings explicitamente aceitos — o que é diferente, e
melhor, de um `GO` que só significa "ninguém olhou".

## Relação com o termination

O termination clássico (`0 crit + ≤2 high`, cobertura, CI streak) continua
valendo — ele é **necessário, não suficiente**. A ordem é:

1. `check-termination.sh` — a contagem fecha?
2. `check-release-gates.sh` — as 11 dimensões fecham?

Release exige os dois. O primeiro pergunta "achamos problema demais?"; o
segundo, "deixamos de olhar para alguma coisa?".

## Saída para o relatório final

A Fase 07 deve reproduzir a tabela de gates **com a coluna de evidência**. Gate
sem evidência é opinião. O relatório afirma "DATABASE: PASS — 6 checks, 0
finding, engine consistente entre infra e runtime", nunca "banco ok".

## Anti-padrões

- ❌ Declarar GO com gates `NOT VERIFIED` sem aceite.
- ❌ Compensar um gate BLOCKED com outros dez em PASS. Não são somáveis.
- ❌ Aceitar warning em `.accept-risk.md` sem nome de quem aceitou e por quê.
- ❌ Marcar `BACKUP_RECOVERY: PASS` porque existe script de backup.
- ❌ Rodar os gates antes dos checks e ler o `NO-GO` de "nada medido" como
  falha do projeto — é falha de ordem de execução.
