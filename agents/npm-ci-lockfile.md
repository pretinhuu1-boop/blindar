---
name: npm-ci-lockfile
category: supply-chain
module: 5
priority: P1
lead: security-lead
authority: implement
description: |
  Build travado no lockfile. `npm install` no Dockerfile ou no CI resolve ranges de novo quando o lockfile diverge — a imagem construída deixa de ser a auditada, e pacote comprometido publicado no meio entra sozinho.
---

# Agent: npm-ci-lockfile

`npm install` num Dockerfile ignora o lockfile quando ele diverge do
`package.json` e **resolve os ranges de novo**. Duas consequências, e as duas
importam:

1. **A imagem de hoje não é a de ontem.** O que foi auditado não é o que subiu, e
   "escaneado" perde o sentido — o scan descreve uma árvore de dependências que
   já não existe.
2. **Um pacote comprometido publicado entre os dois builds entra sozinho.** É
   assim que ataque de cadeia de suprimento chega em produção sem ninguém aprovar
   nada: `^4.19.0` aceita o `4.19.3` que foi publicado ontem à noite.

`npm ci` instala exatamente o que está no lockfile e **falha** se divergir — que
é o comportamento correto num build. O equivalente existe em todo gerenciador:
`--frozen-lockfile` (pnpm), `--immutable` (yarn), `poetry install` com
`poetry.lock`, `pip-sync`.

## O que o check já garante

[`check-npm-ci-lockfile.sh`](../templates/checks/check-npm-ci-lockfile.sh):

| Situação | Severidade |
|---|---|
| Sem lockfile nenhum | **high** |
| Lockfile no `.gitignore` | **high** |
| `npm install` em Dockerfile / CI / Makefile | **med** |
| `pnpm install` ou `yarn install` sem congelar o lock | **med** |

`npm install -g` é ignorado de propósito: instalação global de ferramenta não tem
lockfile de projeto.

Auto-skip em projeto sem `package.json`.

## Por que o lockfile no `.gitignore` é o pior caso

Ele parece o caso mais leve — o arquivo existe na sua máquina, tudo funciona.
Mas para o CI e para o build da imagem **ele não existe**, e a instalação volta a
resolver ranges. O projeto tem toda a aparência de estar travado e nenhuma das
garantias. É o padrão do "default do desconhecido sendo o valor bom": o que
ninguém vê é presumido correto.

## O que só se prova fora do repositório

| Verificar | Por quê |
|---|---|
| Dois builds do mesmo commit dão a mesma imagem | é a definição de reprodutível, e só se prova construindo duas vezes |
| O lockfile do CI é o do repositório | cache de dependência mal configurado restaura outro |
| Dependência com `postinstall` está sob controle | script de instalação roda com as suas permissões |
| Registry apontado é o esperado | `.npmrc` com registry interno muda a origem de tudo |
