---
name: decision-log
category: meta
module: 14
priority: P1
description: |
  Registra decisões arquiteturais em docs/decisions.md (versionado, append-only) com problema, alternativas, decisão, motivo e consequências. Existe porque decisão sem motivo escrito é refeita — e desfeita — a cada sessão nova.
---

# Agent: decision-log

Por que o sistema é assim, e o que já foi descartado.

Existe por um padrão de falha específico: uma decisão tomada com cuidado numa
sessão é revertida na seguinte, porque quem chegou depois não tinha como saber
o que já havia sido considerado. O código mostra **o que** ficou. Não mostra o
que foi rejeitado, nem por quê — e é justamente isso que impede a reversão.

> **Onde mora**: `docs/decisions.md` (ou `docs/adr/`), **versionado**. Nunca em
> `.blindar/`. Decisão arquitetural precisa aparecer no diff, ser revisada no PR
> e sobreviver a um `rm -rf .blindar`.

## Quando ativar

Sempre. E obrigatoriamente antes de fechar qualquer round que:

- escolha ou troque engine de banco, fila, cache, provider de IA;
- mude o modelo de autorização ou de tenancy;
- introduza ou remova um serviço da topologia;
- altere estratégia de deploy, backup ou rollback;
- aceite conscientemente um risco (aí o link é para `.accept-risk.md`);
- **rejeite** uma alternativa que outra pessoa provavelmente proporia de novo.

O último é o mais esquecido e o mais valioso. "Não usamos Redis aqui porque X"
vale tanto quanto "usamos Postgres porque Y".

## Formato de uma entrada

Quatro seções, todas obrigatórias — a verificação determinística em
[`check-decision-log.sh`](../templates/checks/check-decision-log.sh) reprova se
faltar alguma:

```markdown
## 0007 — PostgreSQL em vez de SQLite

### Contexto
Qual era o problema, com números quando houver.

### Alternativas
O que foi considerado e por que cada uma foi descartada.

### Decisão
O que ficou decidido, de forma verificável.

### Consequências
O que isso custa, o que passa a ser possível, o que passa a ser proibido.
```

A seção que mais salva tempo depois é **Alternativas**. Sem ela, a próxima
pessoa recomeça a comparação do zero — e pode chegar a outra conclusão sem
nunca ter visto o argumento original.

## Append-only

Entradas não são editadas nem apagadas. Uma decisão que deixou de valer recebe
uma entrada **nova** que a supersede:

```markdown
## 0012 — Voltar para fila em processo (supersede 0007)
```

Reescrever a entrada antiga apaga a única evidência de que o trade-off foi
avaliado — e o argumento volta, porque nada registra que ele já foi resolvido.

## Relação com o modo de operação

| `operation_mode` | Comportamento |
|---|---|
| `greenfield` | as decisões de G2 nascem aqui, antes de existir código |
| `harden` | decisão tomada durante um round entra no mesmo round |
| `evolve` | **obrigatório antes** de aplicar — sistema em produção não muda de arquitetura sem registro prévio |
| `recovery` | registra o que foi desligado "temporariamente" e o prazo de reversão |

A linha do `recovery` fecha um buraco real: mitigação temporária que ninguém
anotou sobrevive ao incidente e vira permanente.

## Anti-padrões

- ❌ Guardar em `.blindar/` — some no reset e não aparece no PR.
- ❌ Registrar só a decisão, sem alternativas. Não impede a reversão.
- ❌ Editar entrada antiga em vez de superseder.
- ❌ Escrever a ADR depois de implementar, como formalidade. Ela existe para
  informar a escolha, não para justificá-la a posteriori.
- ❌ Uma ADR por commit. O registro é de decisão arquitetural, não de mudança.
