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
| `NOT EXERCISED` | **o estático passou, mas ninguém tocou o sistema no ar** (v0.79.0+) | warning |
| `BLOCKED` | ≥1 finding crit | bloqueio |

### `NOT EXERCISED` — o terceiro estado

Três dimensões respondem perguntas que **nenhuma leitura de repositório
responde**: `RUNTIME`, `RESILIENCE` e `DEPLOYMENT`.

Nelas, um check estático passando prova que a estrutura existe — há código de
breaker, há `try/catch`, há header configurado. Não prova que o breaker segura,
que o `catch` traduz o erro, que o header chega ao browser.

Até a v0.78 isso virava `PASS`, e `PASS` é lido por quem recebe o relatório como
"verificado". Agora, sem nenhum check dinâmico que tenha de fato exercitado o
sistema, a dimensão fica `NOT EXERCISED`:

```
RESILIENCE   NOT EXERCISED   2 check(s) estático(s) sem finding, e nenhum
                             check dinâmico rodou — ninguém tocou o sistema
                             no ar nesta dimensão
```

Quem alimenta essas dimensões com evidência exercitada são os checks dinâmicos
da v0.79 (`chaos-run`, `load-curve`, `redteam-origin`, `deploy-identity`,
`failure-ux`), que declaram `evidence_kind: dynamic` e só contam quando
`exercised: true`. Detalhe em [`docs/dynamic-layer.md`](../docs/dynamic-layer.md).

A lista de dimensões que exigem prova dinâmica é ajustável por
`BLINDAR_DYNAMIC_REQUIRED` — uma biblioteca sem runtime tem motivo legítimo
para reduzi-la. A diferença é que a escolha fica registrada como escolha, em vez
de acontecer por omissão.

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

## Quem fica de fora — e por quê

O `gate_of()` mapeia por glob, não por lista exaustiva: check novo cai num gate
por afinidade de nome em vez de sumir. Sobra, ainda assim, quem não casa. Até a
v0.80 esse resto era um balde só, e o relatório dizia em voz alta **"não contam
pro veredito"** sem que nada acontecesse por causa disso.

Eram 18 checks. Entre eles:

| Check | O que ficava invisível |
|---|---|
| `check-payments` | `crit` de PCI — CVV em código, PAN em log |
| `check-client-bundle-secrets` | `crit` — segredo de provider servido ao browser |
| `check-healthtech-fhir` | `crit` — PHI em log, endpoint FHIR sem auth |
| `check-fintech-banking-br` | `crit` — chave PIX hardcoded, webhook sem verify |
| `check-git-hygiene` | `crit` — `.env` fora do `.gitignore` |
| `check-horizontal-scale` | `high` — sessão em memória, upload em disco local |

É o mesmo defeito que o `severity-contract` pegou em outro degrau: lá o achado
se perdia na string da severidade (`"critical"` fora do enum), aqui no nome do
agente. Nos dois casos o achado existe no JSON e nenhum consumidor o conta.

A partir da v0.81 são **duas listas separadas**, porque misturá-las é o que
fazia ninguém ler nenhuma.

**`out_of_gate` — fora por desenho, com motivo escrito.** Declarado em
`motivo_fora_do_gate()`, mesmo contrato do `motivo_exclusao()` do
`check-selftest.sh`: quem entra precisa responder "o que cobre isso, então?".
São sete, em três famílias:

- **informativos** — `check-strategic-scanner` (Fase 0, nunca emite finding),
  `check-mcp-recommended` (sugere e não instala), `check-ai-powered-example`
  (template para escrever check novo);
- **gate de outra coisa** — `check-wave-guardian` reprova a *run* do blindar,
  não o projeto, e já bloqueia pelo próprio exit code;
- **consultivos** — `check-growth-opportunities`, `check-product-critic` e
  `check-proactive-analysis` são o LLM opinando sobre produto. Um "opportunity"
  que o modelo rotulou `crit` não pode virar NO-GO: opinião entra no relatório,
  não no veredito.

**`unmapped` — buraco, e buraco pesa.** O que sobra é check que roda, acha, e
não chega a dimensão nenhuma. Agora conta como **warning**; se algum deles
trouxer `crit`, conta como **BLOCKED**. Crítico que ninguém conta é crítico que
passa, e "ninguém decidiu onde isso entra" não é aprovação — é a mesma regra do
`NOT VERIFIED`, um degrau acima.

Os dois campos vão para o `gates.json`, para o relatório da Fase 07 poder citar
o que ficou fora: *não citou* não pode ser indistinguível de *não havia*.

A rede de baixo é [`tests/gate-mapping.test.mjs`](../tests/gate-mapping.test.mjs):
falha se qualquer check voltar a cair em `UNMAPPED`, se uma exceção aparecer sem
motivo escrito, ou se a lista de exceções passar de dez.

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

- ❌ Declarar GO com gates `NOT VERIFIED` ou `NOT EXERCISED` sem aceite.
- ❌ Ler `NOT EXERCISED` como "quase PASS". É mais perto de `NOT VERIFIED`: a
  pergunta da dimensão continua sem resposta.
- ❌ Compensar um gate BLOCKED com outros dez em PASS. Não são somáveis.
- ❌ Aceitar warning em `.accept-risk.md` sem nome de quem aceitou e por quê.
- ❌ Marcar `BACKUP_RECOVERY: PASS` porque existe script de backup.
- ❌ Rodar os gates antes dos checks e ler o `NO-GO` de "nada medido" como
  falha do projeto — é falha de ordem de execução.
- ❌ Ler a lista de `unmapped` como ruído. Cada nome ali é um check que rodou
  e cujo achado não chegou a lugar nenhum.
- ❌ Silenciar um `unmapped` movendo o check para `motivo_fora_do_gate()` sem
  responder o que passa a cobri-lo. A exceção existe para nomear a decisão,
  não para esvaziar a lista.
