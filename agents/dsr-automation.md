---
name: dsr-automation
category: compliance
module: 8
priority: P1
lead: privacy-lead
authority: implement
description: |
  O titular consegue exercer o direito dele? Mecanismo de exportação e de eliminação (LGPD art. 18 / GDPR art. 15-17), e eliminação que elimina — soft delete esconde da UI e mantém o dado.
---

# Agent: dsr-automation

LGPD art. 18 e GDPR art. 15–17 dão ao titular direito de **acesso** (receber cópia
do que você guarda) e de **eliminação**. O prazo corre a partir do pedido, não a
partir do dia em que alguém lembrar de escrever o script.

Sem mecanismo, o primeiro pedido vira um `SELECT` manual feito às pressas por um
dev com acesso ao banco de produção — que é exatamente o oposto do que a lei
quer, e cria um segundo problema de privacidade enquanto resolve o primeiro.

A segunda armadilha é "eliminar" com soft delete. `deleted_at = now()` esconde da
UI e mantém o dado. Para o regulador, o dado continua sendo tratado.

## O que o check já garante

[`check-dsr-automation.sh`](../templates/checks/check-dsr-automation.sh):

| Situação | Severidade |
|---|---|
| Sem mecanismo de exportação | **med** |
| Sem mecanismo de eliminação | **med** |
| Eliminação implementada só como soft delete | **med** |

Auto-skip em projeto sem sinal de titular de dado.

## Soft delete não é errado — é insuficiente aqui

O `soft-delete` é a política correta para entidade principal do sistema:
protege contra exclusão acidental, preserva integridade referencial, mantém
histórico. Nada disso muda.

O que muda é que a **rotina do titular** precisa ir além dele. As duas saídas
aceitáveis:

- **Remoção física** dos registros pessoais, com o que a lei exige guardar
  (obrigação fiscal, por exemplo) preservado à parte e justificado;
- **Anonimização irreversível**: o pedido continua existindo para a contabilidade,
  sem ligação recuperável com a pessoa. Trocar o nome por "usuário removido" e
  manter CPF e telefone **não é** anonimização.

## Os lugares que a rotina esquece

Apagar da tabela `users` é a parte fácil. O dado pessoal costuma estar espalhado:

| Onde | O que fica |
|---|---|
| Logs e agregador | ver [`pii-in-logs`](pii-in-logs.md) |
| Backups | não dá para apagar retroativamente — documente a janela de retenção |
| Cache e sessões | Redis com perfil serializado |
| Fila | mensagem pendente com o payload inteiro |
| Provedor externo | CRM, ferramenta de e-mail, analytics: o pedido precisa propagar |
| Anexos e uploads | foto de documento no bucket |

## O que só se prova exercitando

| Verificar | Como |
|---|---|
| A exportação é **completa** | rode contra uma conta real e confira contra o schema |
| A eliminação é verificável | consulte por CPF e telefone depois; se acha, não eliminou |
| O prazo é cumprível | cronometre o processo inteiro, incluindo os provedores externos |
| Há verificação de identidade | rotina de eliminação sem autenticação forte é vetor de ataque |
