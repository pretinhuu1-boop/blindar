---
phase: RECOVERY
title: Modo RECOVERY — sistema quebrado, estabilizar antes de blindar
duration_estimate: variável (minutos a horas)
output: sistema funcional + .blindar/incident.md + entrega ao modo HARDEN
entered_from: 00-mode-select.md
---

# Modo RECOVERY — primeiro parar o sangramento

O pipeline normal do `blindar` **para** quando a suite está vermelha (Fase 1).
Aqui isso é a condição de entrada, não o motivo de abortar.

> **Princípio**: não se refatora durante incêndio. A menor mudança que
> restaura o serviço vence a mudança correta que demora.

Este modo tem uma regra que domina todas as outras: **uma coisa de cada vez**.
Duas correções simultâneas tornam impossível saber qual funcionou.

---

## R1 — Preservar evidência antes de tocar

Antes de qualquer correção, capture o estado — corrigir destrói a prova:

- Mensagem de erro completa, com stack trace.
- Logs da janela do incidente.
- `git log` recente e o último commit que sabidamente funcionava.
- Estado dos containers (`docker ps -a`, logs, exit codes).
- Estado de migrations aplicadas.
- Variáveis de ambiente presentes (**nomes, nunca valores**).

Grave em `.blindar/incident.md`. Esse arquivo é o que permite escrever o
post-mortem depois — e virar check determinístico, pelo processo de
`docs/INCIDENT-TO-CHECK.md`.

---

## R2 — Classificar a falha

| Sintoma | Primeira hipótese |
|---|---|
| Não builda / não compila | dependência, versão, breaking change de lib |
| Builda, não sobe | env faltando, porta, banco inacessível, migration pendente |
| Sobe, não responde | healthcheck, bind de host, proxy, firewall |
| Responde com 500 | migration não aplicada, schema divergente, secret ausente |
| Suite vermelha, app sobe | teste quebrado ≠ app quebrado — classifique qual |
| Intermitente | recurso esgotado (pool, memória, disco), race, timeout |
| Quebrou "sozinho" | dependência flutuante, cert expirado, disco cheio, cron |

"Quebrou sozinho" quase nunca é sozinho: algo mudou fora do repositório.
Certificado, disco, cota, chave rotacionada, dependência sem lock.

---

## R3 — Causa raiz, não sintoma

Pergunte até chegar em algo que explique **todos** os sintomas observados.

Contra-exemplo comum: "o teste falha, então eu ajusto o teste". Se o teste
mudou de comportamento sem que o código de teste mudasse, o teste está
**reportando** o problema, não sendo o problema.

Não prossiga com hipótese que explica só parte do quadro.

---

## R4 — Restaurar com a menor mudança possível

- Uma correção por vez, verificada antes da próxima.
- Se existe um commit sabidamente bom, reverter é resposta legítima e
  frequentemente a melhor.
- **Nada de refatoração oportunista.** Nada de "já que estou aqui".
- **Nada de upgrade de dependência** como correção, a não ser que a causa
  raiz seja exatamente a versão.
- Migration destrutiva: **proibida** neste modo. Restaurar serviço nunca
  justifica perder dado.

### Parada obrigatória

Pare e peça autorização antes de qualquer uma:

- apagar/recriar banco, volume ou índice
- `migrate reset`, `db push --force-reset`, `DROP`
- alterar credencial ou rotacionar secret em produção
- `git push --force`, `reset --hard` em branch compartilhada
- desligar autenticação ou controle de segurança "para testar"

Essa última é a mais perigosa porque parece temporária e sobrevive ao
incidente. Se for inevitável, ela entra no Decision Log com prazo de reversão.

---

## R5 — Provar que voltou

Não basta "não dá mais erro". Prove:

- Build passa.
- App sobe — use `scripts/smoke-run.sh`, que já é o padrão de verdade de
  runtime do `blindar`.
- Healthcheck responde.
- O **fluxo que estava quebrado** funciona ponta a ponta.
- A suite está verde, ou as falhas remanescentes estão explicadas e são
  anteriores ao incidente.

---

## R6 — Estabilizar

Antes de sair do modo RECOVERY:

- A correção está commitada (não só no working tree).
- Existe teste que reproduz a falha e agora passa. Sem esse teste, a mesma
  falha volta.
- `.blindar/incident.md` está completo: sintoma, causa raiz, correção,
  como detectar de novo.
- A causa raiz virou check determinístico, se for generalizável
  (`docs/INCIDENT-TO-CHECK.md`).

---

## R7 — Entregar ao HARDEN

Estabilizado, o modo termina. Reavalie `00-mode-select.md`: normalmente cai em
HARDEN, ou EVOLVE se o sistema estiver em produção.

O que o RECOVERY **não** faz: blindar. Ele devolve o projeto a um estado onde
blindar faz sentido.

---

## Anti-padrões deste modo

- ❌ Corrigir três coisas ao mesmo tempo e não saber qual resolveu.
- ❌ Ajustar o teste para ficar verde sem entender por que ficou vermelho.
- ❌ Refatorar durante o incidente.
- ❌ `migrate reset` como atalho — resolve o sintoma destruindo dado.
- ❌ Declarar resolvido sem prova de runtime.
- ❌ Sair do modo sem teste de regressão: sem ele, a falha só está agendada.
- ❌ Desligar segurança "temporariamente" e não registrar a reversão.
