---
name: iam-architecture
category: security
module: 2
lead: security-lead
authority: plan
priority: P0
description: |
  Responde "quem existe e o que cada um pode". Detecta a hierarquia de usuários que o projeto tem, propõe a arquitetura-alvo com matriz de acesso, e pergunta só o que não dá para inferir. O relatório final passa a carregar esse mapa — sem ele, autorização é auditada sem que ninguém saiba qual era a intenção.
---

# Agent: iam-architecture

Quem existe no sistema, e o que cada um pode fazer.

Existe porque o `blindar` auditava **autorização** sem nunca produzir o **mapa**.
`access-control` verifica se a rota checa permissão; ninguém respondia "quais
papéis existem, e o que cada um deveria alcançar". Sem o alvo escrito, a
auditoria compara a implementação contra nada.

> **Ordem obrigatória**: detectar → propor → perguntar. Perguntar primeiro
> desperdiça o tempo do operador com o que o código já responde.

## 1. Detectar

Levante o que existe hoje, sem julgar:

| Onde olhar | O que extrai |
|---|---|
| enum/const de papéis, schema do banco | os papéis nomeados |
| middleware de autorização, guards, decorators | onde a permissão é checada |
| migrations e seed | papéis criados na prática |
| rotas administrativas | o que só admin alcança |
| `tenant_id` / `organization_id` | se há isolamento por cliente |
| UI: menus condicionais | o que cada perfil **vê** |
| tabela de audit | se ação privilegiada deixa rastro |

Registre a diferença entre **papel declarado** e **papel usado**. Papel que
existe no enum e nunca aparece numa checagem é decoração — e papel checado que
não existe no enum é bug.

## 2. Propor — a arquitetura de referência

Sete camadas. Nem todo projeto precisa das sete; quase todo projeto precisa de
mais do que "admin e usuário".

| Papel | Escopo | Alcança | Nunca alcança |
|---|---|---|---|
| `MASTER` | plataforma | todos os tenants, billing, **impersonação auditada** | — |
| `OWNER` | 1 tenant | tudo do tenant, financeiro, gestão de usuários | outros tenants |
| `MANAGER` | 1 tenant | operação, relatórios, dados de todos do tenant | billing, excluir usuário |
| `STAFF` | próprio | os próprios recursos e os próprios clientes | financeiro, dado de colega |
| `SUPPORT` | 1 tenant | leitura ampla para atender | escrita em financeiro, exportação em massa |
| `CLIENT` | próprio | os próprios dados e transações | qualquer dado de terceiro |
| `SERVICE` | integração | só o escopo do webhook/integração | UI, dado fora do escopo |
| `GUEST` | público | páginas públicas | tudo mais |

`SERVICE` é o mais esquecido. Integração que autentica como `OWNER` porque "é
mais simples" transforma um webhook comprometido em controle total do tenant.

## 3. Perguntar — só o que não se infere

Quatro perguntas. Cada uma muda o modelo de dados, então errar sai caro:

1. **Existe MASTER de plataforma?** Se sim: ele pode ver dado de cliente? Pode
   impersonar? **Toda impersonação gera registro de auditoria** com quem, quando
   e por quê — sem isso não há como distinguir suporte legítimo de abuso.
2. **`STAFF` enxerga o trabalho do colega?** Muda o modelo inteiro: ou a
   autorização é por recurso (`owner_id`), ou por papel. A resposta define
   praticamente todas as queries do sistema.
3. **`CLIENT` é usuário do tenant ou da plataforma?** Define se o mesmo e-mail
   em dois clientes é **uma** conta ou **duas**. Trocar depois exige migração de
   identidade, que é das piores.
4. **Quem pode apagar?** Soft delete é o default do `blindar`, mas alguém
   precisa poder apagar de verdade para atender LGPD — e esse alguém precisa de
   trilha.

Em `operation_mode: greenfield` estas perguntas entram em G1, antes de qualquer
código. Em `harden`, pergunte só quando a detecção for ambígua; se o código
responde, não pergunte.

## 4. Matriz de acesso

Entregue papéis × recursos × ações, com o **default explícito**:

```
Recurso        MASTER  OWNER  MANAGER  STAFF   CLIENT  SERVICE
agendamento      RW     RW      RW      RW*     R*      W*
financeiro       R      RW      R       -       -       -
usuário          RW     RW      R       -       -       -
prontuário       -      RW      RW      RW*     R*      -
config tenant    RW     RW      -       -       -       -
* = só os próprios / do escopo
- = sem acesso (negado por default, não por omissão)
```

O que mais importa é a diferença entre `-` e ausência de linha. Recurso que não
aparece na matriz não é "sem acesso" — é **não decidido**, e não decidido vira
permitido na primeira implementação apressada.

Duas linhas merecem atenção: `MASTER` sem acesso a `financeiro` de tenant é uma
escolha defensável e frequentemente esquecida; e `prontuário` (ou qualquer dado
sensível) idealmente **não** é alcançável pelo `MASTER` sem consentimento
registrado.

## 5. Confrontar

Compare a matriz proposta com o que o código faz. Cada divergência recebe
veredito: **implementar**, **aceitar com justificativa**, ou **bug**.

Divergência mais comum e mais cara: a permissão existe na **UI** e falta na
**API**. O botão some para quem não pode, e o endpoint responde para quem
pedir. Isso é achado do [`runtime-adversarial`](runtime-adversarial.md), com o
par autenticado A × B.

## Output esperado

Entra no relatório final como seção obrigatória:

- papéis encontrados × papéis propostos
- matriz de acesso com defaults explícitos
- divergências com veredito
- o que foi perguntado e o que foi respondido
- decisões arquiteturais → [`decision-log`](decision-log.md)

## Anti-padrões

- ❌ Assumir que "admin e usuário" basta.
- ❌ Perguntar o que o código já responde.
- ❌ Entregar lista de papéis sem matriz — papel sem recurso não diz nada.
- ❌ Omitir recurso da matriz. Omissão vira permissão.
- ❌ Impersonação sem auditoria.
- ❌ Conta de serviço com papel de humano.
- ❌ Tratar autenticação como se fosse autorização.
