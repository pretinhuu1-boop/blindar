# Camada dinâmica — evidência exercitada × evidência estática

> Introduzida na v0.79.0. Irmã de [`deterministic-layer.md`](deterministic-layer.md).

## O problema que ela resolve

Até a v0.78 o blindar tinha 115 templates de check: 101 shell puro e 14
`.api.sh`. Os 101 são determinísticos de verdade — exit code próprio, result
JSON, sem depender do LLM. Mas **97 deles leem o repositório**.

Ler o repositório prova que a **estrutura existe**:

- há código de circuit breaker
- há `try/catch` no handler
- há header de segurança configurado
- há `TRUST_PROXY` restrito

Nenhuma dessas leituras prova que o breaker **segura**, que o `catch`
**traduz** o erro para algo utilizável, que o header **chega** ao browser, ou
que o `TRUST_PROXY` **resiste** a um `X-Forwarded-For` forjado vindo de outra
origem de rede.

O gate lia `passed` e escrevia `PASS`. E `PASS` é lido por quem recebe o
relatório como "verificado".

## O vocabulário novo

Todo result passa a carregar dois campos:

```json
{ "evidence_kind": "static" | "dynamic",
  "exercised": true | false,
  "not_exercised_reason": "sem alvo: passe --url, ..." }
```

| Campo | Significado |
|---|---|
| `evidence_kind: static` | o check leu o repositório |
| `evidence_kind: dynamic` | o check se propõe a tocar o sistema no ar |
| `exercised: true` | tocou e mediu |
| `exercised: false` | não tocou — e `not_exercised_reason` diz por quê |

### A regra que o `_lib.sh` aplica sozinho

Check dinâmico com `exercised: false` **nunca** sai `passed`. O `emit_result`
rebaixa para `skipped` e registra o motivo.

Isso é a mesma disciplina do `require_tool` — sem ferramenta não há veredito —
aplicada à pré-condição de runtime em vez de à de ferramenta. "Não medi" não
pode ser gravado com o mesmo status de "medi e estava bom".

Não depende de cada autor de check lembrar: a regra vive no ponto por onde todo
check passa.

## O estado `NOT EXERCISED` no gate

Três dimensões só fecham com medição de runtime:

| Gate | Pergunta que só o sistema no ar responde |
|---|---|
| `RUNTIME` | o que o código afirma acontece de fato quando roda? |
| `RESILIENCE` | o que acontece quando uma dependência cai? |
| `DEPLOYMENT` | o artefato no ar é o que foi auditado? |

Nelas, checks estáticos passando **não** produzem `PASS`. Produzem:

```
RESILIENCE   NOT EXERCISED   2 check(s) estático(s) sem finding, e nenhum
                             check dinâmico rodou — ninguém tocou o sistema
                             no ar nesta dimensão
```

Os quatro estados, em ordem de informação:

| Estado | Significa |
|---|---|
| `BLOCKED` | mediram e acharam crítico |
| `NOT VERIFIED` | nenhum check da dimensão executou |
| `NOT EXERCISED` | o estático passou, o dinâmico não chegou a medir |
| `PASS` | mediram, inclusive contra o sistema no ar |

`NOT EXERCISED` conta como warning e é dispensável por aceite assinado em
`.accept-risk.md` — nunca por default. Ele é ajustável por
`BLINDAR_DYNAMIC_REQUIRED` para quem tem motivo (uma lib sem runtime, por
exemplo), e essa escolha fica registrada como escolha.

## Os cinco checks dinâmicos

| Check | Exercita | Reprova quando |
|---|---|---|
| `check-chaos-run` | congela a dependência (`docker pause`) | trava > 5s, blast radius total, ou não recupera |
| `check-load-curve` | rampa de concorrência | joelho de saturação abaixo do alvo |
| `check-redteam-origin` | container atacante na rede do alvo | rota interna alcançável, XFF forjado concede acesso |
| `check-deploy-identity` | lê a identidade de build no health | diverge do commit auditado, ou não declara |
| `check-failure-ux` | provoca falhas e lê a resposta | 500 onde cabia 404, rastro vazado, 401 por falha de infra |

Todos aceitam `--url`, `BLINDAR_TARGET_URL` ou `.blindar/target.url`.

## Segurança: o experimento não pode virar o incidente

`check-chaos-run` e `check-failure-ux` congelam containers. Eles **não**
escolhem por semelhança de nome.

`dyn_pick_dependency` só devolve container amarrado ao alvo: mesmo projeto
compose de quem publica a porta do alvo, ou o que o operador passou em
`--service`. Sem esse vínculo, o check sai `NOT EXERCISED` em vez de adivinhar.

A razão é concreta: na primeira execução real deste check, a seleção por padrão
de nome congelou um Redis de outro projeto da máquina. Um check de resiliência
causando exatamente o incidente que deveria estar medindo.

`dyn_freeze` instala `trap ... EXIT INT TERM` — Ctrl+C no meio do experimento
descongela antes de sair.

## Como testar um check dinâmico

Par de fixture em disco não serve: o insumo é um processo respondendo errado.

`tests/fixtures/dyn-server.mjs` sobe o alvo nos dois modos (`bad` e `good`), e
`tests/dynamic-evidence.test.mjs` prova, contra execução real, que o check
dispara no defeituoso e cala no correto.

O servidor precisa ser **processo separado**: o teste usa `spawnSync`, que
bloqueia o event loop do Node. Um servidor no mesmo processo ficaria sem aceitar
conexão justamente durante a medição, e todo probe voltaria `000` — foi assim
que a primeira versão desse teste "provou" que os checks não exercitavam nada.

## Os três checks de disciplina

Não são dinâmicos, mas fecham o mesmo buraco pelo lado do processo:

| Check | Gateia |
|---|---|
| `check-negative-control` | toda correção tem controle negativo executado (quebrei de propósito, o teste caiu) |
| `check-assumption-probe` | a premissa do achado foi medida antes de virar obra |
| `check-report-integrity` | o laudo se corrige quando a medição o contradiz |

Os três leem registros em `.blindar/` e, sem esses registros, saem `skipped`
com `missing_tool` preenchido — cobertura ausente, nunca aprovação.

## A regra que amarra tudo

> Dimensão dinâmica só conta como verde depois de **EXECUTADA e MEDIDA** contra
> o sistema no ar. Playbook `.md` vale `NOT VERIFIED`. Check estático que passou
> vale `NOT EXERCISED`. Nenhum dos dois vale `PASS`.

É a extensão direta da regra que o blindar já aplicava a ferramenta ausente e a
"zero checks rodados" — agora aplicada à diferença entre ler o código e derrubar
o sistema.
