---
phase: FEATURE
title: Modo FEATURE — adicionar capacidade a um projeto que já existe
duration_estimate: variável
output: feature implementada + checks sobre o diff + matriz de acesso atualizada
entered_from: 00-mode-select.md
---

# Modo FEATURE — construir dentro de casa habitada

Os outros modos auditam (`harden`), constroem do zero (`greenfield`), protegem
produção (`evolve`) ou apagam incêndio (`recovery`). Faltava o caso mais comum
do dia a dia: **acrescentar algo a um projeto existente e saudável**.

Sem este modo, pedir "implementa o módulo de pagamento" caía no `harden` — que
é auditoria, não construção. O resultado era código escrito sem a disciplina do
`greenfield` e um relatório que auditava o projeto inteiro em vez do que mudou.

> **Princípio**: a feature nasce dentro das regras que o projeto já segue, e
> prova que não degradou nada do que já funcionava.

## Como se entra aqui

Diferente dos outros quatro. `recovery`, `greenfield` e `evolve` são detectados
pelo **estado do repositório**. Este é detectado pela **intenção do pedido** —
um projeto saudável que vai receber uma feature é indistinguível, no disco, de
um projeto saudável que vai ser auditado.

Sinais no pedido: "implementa", "adiciona", "cria a tela de", "quero um módulo
de", "preciso que o sistema também faça".

Precedência preservada: se o projeto está quebrado, `recovery` vence — não se
constrói sobre escombro, mesmo que o pedido seja de feature. Se está vazio,
`greenfield` vence.

**Se o projeto está em produção**, este modo **compõe** com o `evolve` em vez de
substituí-lo: a disciplina de construção daqui, somada às travas de lá (round
≤40 LOC, `supervised`, migration destrutiva proibida). Feature em sistema com
usuários é as duas coisas ao mesmo tempo.

---

## F1 — Entender antes de escrever

A feature não nasce no vazio: ela toca o que já existe. Antes de qualquer
arquivo, responda com o código na mão:

- Onde isso encaixa na arquitetura atual? Que módulo, que camada?
- Já existe algo parecido no projeto? **Siga o padrão que está lá**, mesmo que
  você preferisse outro — consistência vale mais que preferência, e um projeto
  com dois padrões é pior que um projeto com o padrão errado.
- Que convenções o projeto usa: nomes, estrutura de pasta, tratamento de erro,
  formato de resposta, jeito de validar entrada?
- Que dado já existe e pode ser reaproveitado, em vez de duplicado?

Rodar o [`graph-builder`](../agents/graph-builder.md) aqui é barato e evita a
feature que reimplementa o que já havia.

## F2 — Impacto, antes de escrever

Obrigatório se a feature toca schema, contrato de API, autorização, fila ou
configuração. É o [`change-impact`](../agents/change-impact.md) inteiro, com
atenção às duas linhas que sempre escapam: **seed/dados simulados** e
**mensagem em voo** durante o deploy.

A classificação de risco do [`risk-engine`](../agents/risk-engine.md) vale aqui
como em qualquer round: `HIGH` e `CRITICAL` pausam mesmo em `auto`.

## F3 — A feature nasce dentro das regras

O que no `greenfield` são etapas de construção, aqui são **requisitos de
aceitação da feature**. Nenhum deles é "depois":

| Dimensão | O que a feature já nasce tendo |
|---|---|
| Autorização | quem pode, verificado na **API** e não só na UI |
| Multi-tenant | `tenant_id` desde a primeira migration, se o projeto for |
| Dados | soft delete, índice nas FKs, migration **reversível** |
| Seed | dado simulado vai para o **banco**, nunca array no código |
| Entrada | validada na borda |
| Erro | try-catch no handler, mensagem acionável |
| Listagem | paginada |
| Assíncrono | fila com retry (3), backoff, DLQ e **idempotência** |
| Auditoria | ação sensível deixa rastro |
| UI | empty state, skeleton, confirmação em ação destrutiva, ≥44px, WCAG AA |
| Teste | escrito junto, cobrindo caminho principal e o de erro |
| Observabilidade | log estruturado com correlation ID |

**Nenhum botão sem handler real. Nenhum "salvo!" que não salvou.**

## F4 — A matriz de acesso ganha linha

Feature quase sempre traz **recurso novo**. Todo recurso novo entra na matriz do
[`iam-architecture`](../agents/iam-architecture.md), com o acesso de cada papel
declarado explicitamente.

Recurso que não aparece na matriz não é "sem acesso" — é **não decidido**, e não
decidido vira permitido na primeira implementação apressada. Este é o momento em
que a linha nasce; adicioná-la depois é adivinhar o que já foi feito.

## F5 — Provar que a feature funciona

Não "o código está lá". Ponta a ponta: a ação pela interface (ou pela API)
produz o efeito esperado, o dado persiste, e sobrevive a um restart.

Se a feature tem UI, ela é exercitada — o botão é clicado. O
[`functional-e2e`](../agents/functional-e2e.md) existe para isso.

## F6 — Provar que não quebrou o que já existia

A parte que separa este modo de "escrever código":

1. **Suite inteira verde**, não só os testes novos.
2. **Checks sobre o diff**: `blindar-run.sh --since <ref>`. É o modo diff, que
   roda os checks sobre os arquivos que mudaram em vez do projeto inteiro —
   feedback em minutos, e o relatório fala da feature, não do passado do projeto.
3. **Nenhuma defesa existente degradada.** Este é o gate `security-first` do
   `blindar`: um PR que não é de segurança não pode enfraquecer segurança. Vale
   integralmente aqui.
4. Se a feature mexeu em algo compartilhado, rode o pipeline completo — o `--since`
   não enxerga o que quebrou longe do diff.

## F7 — Registrar

Decisão arquitetural tomada durante a feature (escolha de biblioteca, padrão de
integração, formato de evento) entra em `docs/decisions.md` no **mesmo round**.
Ver [`decision-log`](../agents/decision-log.md).

Documentação e `.env.example` acompanham. Feature que exige variável nova sem
declará-la quebra o próximo `git clone`.

---

## Diferença para os outros modos, em uma linha cada

| Modo | Pergunta |
|---|---|
| `greenfield` | como construo isto do zero, já certo? |
| `harden` | o que está errado no que existe? |
| `evolve` | como mexo sem quebrar quem está usando? |
| `recovery` | como faço voltar a funcionar? |
| **`feature`** | **como acrescento isto sem estragar o resto?** |

## Anti-padrões deste modo

- ❌ Introduzir um padrão novo porque você prefere. Siga o do projeto.
- ❌ Auditar o projeto inteiro quando o pedido era uma feature — use `--since`.
- ❌ Deixar autorização "para depois de as telas ficarem prontas".
- ❌ Mock para destravar. Dado simulado vai no banco, via seed.
- ❌ Rodar só os testes novos e declarar pronto.
- ❌ Esquecer a linha na matriz de acesso.
- ❌ Migration sem `down` — o [`check-destructive-migration`](../templates/checks/check-destructive-migration.sh) reprova, e com razão.
- ❌ Tratar feature em produção como feature comum: lá, este modo compõe com o `evolve`.
