---
phase: COLLAB
title: Modo COLLAB — preparar o repositório para uma equipe
duration_estimate: ~30 min
output: repositório versionado, protegido, documentado e com CI
entered_from: 00-mode-select.md
---

# Modo COLLAB — o repositório é o problema

Os outros modos tratam do **código**. Este trata do **repositório e do processo**:
quando o projeto funciona mas ninguém além de quem escreveu consegue contribuir
com segurança.

Sintomas que trazem para cá: nenhum commit, ou um único "initial commit" com o
projeto inteiro; `.env` versionado; sem CI; sem `.gitignore`; história com autor
único; branches paradas há meses; ninguém sabe quem revisa o quê.

> **Assimetria que governa este modo**: quase tudo em git é reversível, e três
> coisas não são — segredo commitado, histórico reescrito depois de publicado, e
> trabalho alheio sobrescrito.

Conduzido por [`git-collaboration`](../agents/git-collaboration.md), com o
[`check-git-hygiene`](../templates/checks/check-git-hygiene.sh) cobrindo a parte
determinística.

---

## C1 — Parar o sangramento antes de commitar

**Ordem importa e não é negociável.** Se há segredo no diretório e o repositório
ainda não tem commit, esta é a única janela em que dá para evitar o problema em
vez de remediar.

1. `.gitignore` **primeiro** — `.env*`, `node_modules/`, `dist/`, `build/`,
   `coverage/`, `.next/`, `*.log`, `data/`, `uploads/`.
2. `.env.example` com as **chaves** e sem os valores.
3. Só então o primeiro `git add`.

Se já houver commit com segredo: ele está no histórico e **apagar o arquivo não
resolve**. Trate a credencial como comprometida, **rotacione**, e só depois
decida se vale reescrever o histórico. A rotação é a parte obrigatória; a
reescrita é a opcional.

## C2 — Primeiro commit legível

Um "initial commit" com 800 arquivos não é história — é um retrato. Não dá para
bisect, culpar linha nem reverter parte.

Se o projeto ainda não tem commits, vale separar em alguns commits temáticos:
scaffold/config, backend, frontend, infra, docs. Não precisa reconstruir o
passado que não existiu; precisa que o ponto de partida seja navegável.

## C3 — Nada entra em `main` sem passar por algo

- Proteção de branch em `main`: sem push direto, PR obrigatório, CI verde
  obrigatória, e branch atualizada antes do merge.
- CI mínima que roda **de verdade**: install, lint, type-check, testes, build.
  CI que só faz checkout dá a sensação de proteção sem a proteção.
- Estratégia de merge escolhida e escrita (squash costuma ser a melhor para
  equipe pequena: um PR vira um commit legível em `main`).

## C4 — A equipe sabe o que fazer sem perguntar

- `README` que permite a outra pessoa **subir o projeto** — pré-requisitos,
  variáveis, comandos. O teste é literal: alguém que nunca viu o projeto
  consegue rodá-lo lendo só isso?
- `CONTRIBUTING` com padrão de branch, de commit e de PR.
- `CODEOWNERS` para o PR encontrar revisor sozinho.
- Template de PR e de issue.
- `CHANGELOG` se há release.

## C5 — Ônibus factor

Histórico com autor único é risco operacional, não estilo. Nomeie o que só uma
pessoa sabe (deploy, credenciais, integração frágil) e transforme em runbook.
Este modo termina quando **a segunda pessoa consegue trabalhar sem a primeira**.

## C6 — Entregar ao modo seguinte

O `COLLAB` arruma o repositório; não audita o código. Terminado, reavalie o
modo: normalmente `harden` (agora dá para blindar com PRs revisáveis) ou
`feature`.

---

## Anti-padrões

- ❌ Commitar antes do `.gitignore`. Inverte a única ordem que importa.
- ❌ Achar que apagar o `.env` num commit seguinte resolve. Não resolve, e a
  credencial já vazou.
- ❌ Reescrever histórico já publicado sem combinar — todo mundo reclona.
- ❌ CI que não roda teste. Dá sensação de proteção sem proteção.
- ❌ Proteger `main` e deixar a exceção "admins podem forçar".
- ❌ `CONTRIBUTING` que descreve um processo que a equipe não segue. Pior que
  não ter, porque quem chega acredita.
- ❌ Auditar o código neste modo. Isto aqui é o repositório; o código é do
  `harden`.
