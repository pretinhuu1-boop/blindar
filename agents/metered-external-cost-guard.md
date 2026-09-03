---
name: metered-external-cost-guard
category: ops
module: 6
priority: P1
lead: sre-lead
authority: implement
description: |
  Bomba de custo: serviço externo cobrado por uso (LLM, voz, SMS, e-mail, OCR) chamado sem cota POR ORIGEM. Rate limit global protege o servidor; cota por tenant/chave é o que impede uma origem de gastar o orçamento de todas.
---

# Agent: metered-external-cost-guard

Serviço externo cobrado por uso tem uma propriedade que serviço próprio não tem:
**cada requisição sai do seu bolso, e o teto é o limite do cartão**.

Sem cota por origem — por tenant, por conta, por chave — basta um cliente em
laço, um bot raspando, ou um bug de retry para consumir o orçamento do mês numa
tarde. E a conta chega no fim do ciclo, quando já não há o que fazer além de
pagar.

**Rate limit global não resolve o problema certo.** Ele protege o *seu servidor*
de sobrecarga. A cota por origem impede *uma origem* de gastar o dinheiro de
todas as outras. São controles diferentes, com finalidades diferentes, e ter o
primeiro não substitui o segundo.

## O que o check já garante

[`check-metered-external-cost-guard.sh`](../templates/checks/check-metered-external-cost-guard.sh):

| Situação | Severidade |
|---|---|
| Serviço cobrado por uso sem nenhuma cota | **med** |
| Cota existe, mas não chaveada por origem | **med** |

Aceita como cota por origem: contador ou limite ligado a tenant/loja/conta/
usuário/organização/chave, ou rate limit com `keyGenerator` por identidade.

O roster de serviços cobrados por uso está marcado no check com
`revisar trimestralmente — últ. revisão: 2026-09`. Fornecedor fora dele não é
"aprovado": a lista reduz falso-negativo, não define o universo.

Auto-skip em projeto sem serviço externo cobrado por uso.

## O desenho que funciona

1. **Cota é lida antes da chamada**, não depois. Contar o gasto sem impedi-lo é
   relatório, não controle.
2. **A chave da cota é a identidade que paga** — a loja, a conta, o workspace.
   Chavear por usuário quando quem paga é a empresa deixa a soma sem teto.
3. **Reserva antes, ajuste depois.** Em serviço tokenizado o custo real só é
   conhecido na resposta: reserve uma estimativa, debite o real quando voltar.
4. **A negativa é uma resposta do produto**, não um 500. "Cota do mês esgotada,
   fale com o administrador" é uma tela; erro genérico é um ticket.
5. **Teto de emergência global** além do por-origem: alarme e desligamento
   automático se o total do dia passar de N.

## O que só se prova fora do repositório

| Verificar | Por quê |
|---|---|
| Alerta de orçamento no painel do provedor | é a última rede, e é do lado deles |
| Chave de API separada por ambiente | dev batendo na chave de produção some no agregado |
| O custo por tenant é observável | sem isso não dá para saber quem custa quanto |
| Retry não multiplica o custo | três tentativas são três cobranças |
