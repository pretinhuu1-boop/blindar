---
name: deps-auto-update
category: security
module: 5
priority: P1
lead: security-lead
authority: implement
description: |
  Dependabot ou Renovate configurado. Sem monitoramento contínuo, a dívida de CVE não é descoberta — é acumulada em silêncio até a próxima auditoria manual, quando atualizar já virou projeto.
---

# Agent: deps-auto-update

Sem monitoramento contínuo, ninguém descobre que uma dependência ficou
vulnerável: descobre-se que ela ficou vulnerável **há dezoito meses**, no dia em
que alguém finalmente roda um scanner.

Aí não é mais atualizar um pacote — é atravessar dez versões maiores de uma vez,
com quebra de API em cada uma. Foi o caso do Electron 34 → 44 numa auditoria
real: 48 CVEs acumulados, e a correção deixou de ser um comando para virar um
projeto com build, teste e regressão.

O custo de atualizar cresce mais rápido que o intervalo entre atualizações. É a
única dívida técnica com juros compostos e prazo definido por terceiros.

Divisão com o [`patch-management`](patch-management.md): lá é a política (feed de
CVE, SLA por severidade, runtime e SO). Aqui é o mecanismo — existe robô abrindo
PR, ou não existe?

## O que o check já garante

[`check-deps-auto-update.sh`](../templates/checks/check-deps-auto-update.sh):

| Situação | Severidade |
|---|---|
| Sem `dependabot.yml` e sem `renovate.json` | **med** |
| `dependabot.yml` sem nenhum `package-ecosystem` | **med** |
| `dependabot.yml` sem `schedule.interval` | **low** |

O segundo caso importa mais do que parece: **config presente e inerte é pior que
config ausente**, porque some da lista de pendências. O arquivo existe, o
checklist marca verde, e nada é monitorado.

Auto-skip em projeto sem manifesto de dependências.

## Configuração que funciona

- **Um `package-ecosystem` por gerenciador de fato usado.** Projeto poliglota com
  só `npm` declarado deixa Python, Docker e Actions sem cobertura.
- **`interval: weekly`**, não `daily`: PR diário vira ruído e o time desliga.
- **Agrupar atualizações de patch** (`groups`) reduz volume sem perder cobertura.
- **Alerta de segurança sempre imediato**, independente do intervalo escolhido.

## O que só se prova fora do repositório

| Verificar | Por quê |
|---|---|
| Os PRs são **mergeados** | robô abrindo PR que ninguém revisa é fila, não cobertura |
| O CI roda nos PRs do robô | atualização sem teste é aposta |
| Alerta de segurança ligado no repositório | é configuração do provedor, não do arquivo |
