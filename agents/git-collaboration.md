---
name: git-collaboration
category: dx
module: 14
lead: release-lead
authority: implement
priority: P0
description: |
  Disciplina de git, GitHub e trabalho em equipe: commit que explica o porquê, PR revisável, conflito resolvido sem perder trabalho alheio, e documentação que acompanha o código. Vale em TODOS os modos — não é etapa, é como o trabalho é feito.
---

# Agent: git-collaboration

O repositório é a memória da equipe. Ela precisa ser legível daqui a um ano.

Não é uma fase do pipeline: é **como** o trabalho é feito em qualquer modo. O
[`check-git-hygiene`](../templates/checks/check-git-hygiene.sh) cobre o que se
vê no sistema de arquivos; este playbook cobre o que exige a história do git e o
julgamento.

> **Assimetria que governa tudo aqui**: quase tudo em git é reversível, e três
> coisas não são — segredo commitado, histórico reescrito depois de publicado, e
> trabalho alheio sobrescrito. Trate essas três com cuidado desproporcional.

## O que só se vê com o git na mão

O check não alcança; aqui é obrigatório verificar:

| Verificar | Por quê |
|---|---|
| Segredo **no histórico** (`git log -p`, gitleaks `--no-git` vs histórico) | remover num commit seguinte **não** remove do histórico nem dos clones já feitos |
| Binário grande no histórico | todo clone baixa todas as versões, para sempre |
| Branches divergentes há semanas | quanto mais tempo, mais caro o merge — e mais provável que alguém desista e sobrescreva |
| `main` sem proteção | qualquer push direto derruba o trabalho de quem estava no meio |
| Commits diretos em `main` sem PR | ninguém revisou |
| Autor único em todo o histórico | ônibus factor 1 |

Segredo no histórico **não se resolve com um commit**. Exige reescrita de
histórico e **rotação da credencial** — a credencial deve ser considerada
comprometida desde o momento em que foi publicada, mesmo em repositório privado.

## Commit

A mensagem responde **por que**, não o que — o diff já diz o que.

```
fix(auth): sessão não expirava em aba aberta

O timer só corria com a aba em foco, então quem deixava o sistema aberto
ficava logado indefinidamente. Passa a validar no servidor a cada request.
```

- Um commit, uma ideia. Refactor + feature + fix juntos são irrevisáveis, e
  impossíveis de reverter separadamente.
- Conventional commits (`feat`, `fix`, `docs`, `refactor`, `test`, `chore`).
- Nunca `git commit -m "ajustes"`, `"wip"`, `"correções"`. Daqui a seis meses
  esse commit é indistinguível de qualquer outro, e é justamente ele que a
  bisect vai apontar.
- **Nunca `--no-verify`.** O hook existe porque alguém já pagou o preço. Se
  atrapalha, conserte o hook.

## Branch

`tipo/escopo-curto` — `feat/agendamento-recorrente`, `fix/timeout-sessao`.

Curta e integrada rápido. Branch que vive semanas diverge, e o merge fica caro
justamente quando a pressa é maior. Antes de começar e antes de abrir o PR:
`git fetch && git rebase origin/main` — resolver conflito pequeno agora custa
menos que o acúmulo depois.

## Pull request

Revisável significa que **cabe na cabeça de quem revisa**: um assunto, e
tamanho que dá para ler com atenção. Acima de ~200 linhas de mudança real,
quebre — PR grande recebe aprovação sem leitura, o que é pior que não ter
revisão, porque cria a ilusão de que houve.

O corpo diz: **o que muda**, **por que**, **como foi testado**, e **o que pode
quebrar**. O último é o mais útil ao revisor e o mais omitido.

## Conflito

A regra que mais evita perda de trabalho: **conflito se resolve entendendo os
dois lados**, nunca escolhendo um às cegas.

`--ours` e `--theirs` resolvem o marcador e descartam a intenção do outro lado.
Quem escreveu aquilo tinha um motivo; se o motivo não é óbvio, pergunte. Depois
de resolver, **rode os testes** — conflito resolvido compila e mesmo assim
quebra comportamento com frequência.

Se os dois lados mexeram no mesmo lugar por razões diferentes, o resultado quase
nunca é um dos dois: é um terceiro texto que contempla as duas intenções.

## O que exige combinar antes

- `push --force` em branch compartilhada. Use `--force-with-lease`, que recusa
  se alguém publicou algo que você não viu.
- Rebase de branch já publicada — muda o SHA de commits que outra pessoa já tem.
- `reset --hard` em branch compartilhada.
- Reescrita de histórico (`filter-branch`, `filter-repo`) — todo mundo precisa
  reclonar.
- Apagar branch remota que não seja sua.

## A documentação acompanha o código

No mesmo PR, não "depois":

- `README` quando muda como se roda o projeto
- `.env.example` quando entra variável nova — sem isso o próximo `git clone`
  não sobe
- `CHANGELOG` quando muda o comportamento observável
- [`decision-log`](decision-log.md) quando a decisão foi arquitetural
- Migration com `down` — ver [`check-destructive-migration`](../templates/checks/check-destructive-migration.sh)

Documentação atrasada não fica atrasada: fica **errada**, e errada é pior que
ausente, porque alguém confia nela.

## Por modo de operação

| `operation_mode` | O que muda |
|---|---|
| `greenfield` | `.gitignore` e CI no **primeiro** commit, antes de qualquer segredo existir |
| `harden` | um vetor por PR — misturar impede o revisor de avaliar a defesa |
| `feature` | a feature inteira em PR próprio, com docs junto |
| `evolve` | PR menor ainda, e o corpo diz explicitamente o caminho de volta |
| `recovery` | commit da correção **separado** de qualquer limpeza, para poder reverter só ela |

## Anti-padrões

- ❌ `--no-verify` para "destravar".
- ❌ Resolver conflito com `--ours`/`--theirs` sem ler o outro lado.
- ❌ `push --force` puro em branch compartilhada.
- ❌ Commit "wip"/"ajustes"/"correções".
- ❌ Achar que apagar o arquivo num commit seguinte remove o segredo. Não
  remove — e a credencial já vazou.
- ❌ PR que mistura refactor com feature.
- ❌ Branch viva por semanas.
- ❌ Documentação "no próximo PR".
- ❌ Commitar `node_modules`, `dist` ou `.env`.
