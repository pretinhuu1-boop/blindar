# Como usar o blindar — guia completo

Documento de referência: do zero ao projeto blindado.

---

## Índice

1. [Instalação](#1-instalação)
2. [Pré-requisitos no projeto-alvo](#2-pré-requisitos-no-projeto-alvo)
3. [Primeiro uso — passo a passo](#3-primeiro-uso--passo-a-passo)
4. [Durante a execução — o que esperar](#4-durante-a-execução--o-que-esperar)
5. [Acompanhar via `sec.html`](#5-acompanhar-via-sechtml)
6. [Parar / pausar / retomar](#6-parar--pausar--retomar)
7. [Quando o skill termina](#7-quando-o-skill-termina)
8. [Casos especiais](#8-casos-especiais)
9. [Rodar em outras AIs (ChatGPT/Gemini/Cursor)](#9-rodar-em-outras-ais)
10. [Atualização do skill](#10-atualização-do-skill)
11. [Troubleshooting](#11-troubleshooting)
12. [Comandos úteis](#12-comandos-úteis)

---

## 1. Instalação

### Windows (PowerShell)

```powershell
git clone https://github.com/pretinhuu1-boop/blindar.git "$env:USERPROFILE\.claude\skills\blindar"
```

ou via script:

```powershell
iwr -useb https://raw.githubusercontent.com/pretinhuu1-boop/blindar/main/scripts/install.ps1 | iex
```

### Linux / macOS

```bash
git clone https://github.com/pretinhuu1-boop/blindar.git ~/.claude/skills/blindar
```

### Verificar

Abra o Claude Code em qualquer pasta e digite:

```
/skills
```

Deve listar `blindar`. Se não aparecer, ver [Troubleshooting](#11-troubleshooting).

---

## 2. Pré-requisitos no projeto-alvo

O skill **se recusa a rodar** se algum desses não for verdadeiro:

| Requisito | Como verificar | Por quê |
|---|---|---|
| É repo Git | `git status` funciona | skill cria branches e PRs |
| `git status` limpo | sem mudanças não-commitadas | rounds vão sobrepor seu trabalho |
| Suite de testes existe e está **verde** | `pytest`, `npm test`, etc. passa | não dá pra blindar projeto quebrado |
| CI configurada | `.github/workflows/` ou equivalente | rounds aguardam CI verde antes de mergear |
| Permissão de merge | você consegue fazer `gh pr merge --squash` | skill mergeia cada round |
| Branch ativa | normalmente `main` (configurável) | onde rounds vão pousar |

Se faltar algo, o skill **para na Fase 0 (baseline)** e te diz o que faltou. Sem adivinhar.

---

## 3. Primeiro uso — passo a passo

### 3.1. Vá para a pasta do projeto

```powershell
cd C:\projetos\meu-app
```

### 3.2. Verifique pré-requisitos

```powershell
git status              # deve estar limpo
pytest -q               # ou npm test, deve passar
```

### 3.3. Abra o Claude Code e invoque o skill

Digite **uma** das frases-gatilho:

- `blindar`
- `blinda este projeto`
- `deixa pronto pra produção`
- `production ready`
- `harden this project`

### 3.4. Confirme se for perguntado

Em modo padrão Claude Code pede permissão pra ações sensíveis (rodar Bash,
gh, criar branches). Confirmar. **O skill em si não pede confirmação a
cada round — só o harness do Claude.**

Se quiser autonomia total, use modo `--accept-edits` ou similar do Claude
Code.

### 3.5. Deixe rolar

O skill agora roda do começo ao fim. Você acompanha em **3 lugares**:

- **Terminal do Claude Code** — narração curta de cada fase
- **Browser com `sec.html`** — dashboard vivo
- **GitHub PRs** — cada round é um PR mergeado

---

## 4. Durante a execução — o que esperar

### Cronograma típico (projeto médio, ~50k LOC)

| Fase | Duração | O que acontece |
|---|---|---|
| 0 — Baseline | ~2 min | Detecta stack, conta testes, conferência |
| 1 — Discovery | ~3 min | 3 agentes paralelos mapeiam tudo |
| 2 — Bootstrap sec.html | ~1 min | PR único com dashboard |
| 3 — Loop de rounds | **horas a dias** | 1 PR a cada ~20-60 min |
| 4 — Adversarial review | ~10 min cada 10 rounds | tentativa de refutar |
| 5 — Production checklist | ~3 min | gates finais |
| 6 — Relatório final | ~2 min | PR de sumário |

### Saída no terminal — exemplo real

```
[Fase 0] Baseline...
  stack: python+postgres
  tests: 142 passando, 0 falhas
  type-check: clean
  git: clean
  CI: github-actions
  ✓ pode prosseguir

[Fase 1] Discovery (3 agentes paralelos)...
  ✓ inventory: 47 endpoints, 8 externals
  ✓ threat-model: 31 ATKs aplicáveis (12 crit, 14 high, 5 med)
  ✓ architecture: monolito Flask + Postgres + Redis + Cloudflare

[Fase 2] Bootstrap sec.html...
  ✓ docs(blindar): bootstrap sec.html dashboard #142 (mergeado)

[Fase 3] Round 1/?
  pick: ATK-003 (crit) — TOTP reuse window
  agente: access-control
  implementing... 4 files, 67 LOC, 4 tests
  ✓ sec(auth): close ATK-003 — TOTP reuse window #143 (mergeado)

[Fase 3] Round 2/?
  pick: ATK-018 (crit) — Idempotency-Key faltando em /api/charge
  ...
```

### Frequência de PRs

- 1 PR a cada 20-60 min na média (varia com stack, CI duration, tamanho do gap)
- Em 8 horas: ~10-20 rounds
- Projeto saudável termina em 2-5 dias úteis de execução

---

## 5. Acompanhar via `sec.html`

Após Fase 2, abre `sec.html` na raiz do projeto:

```powershell
start sec.html      # Windows
open  sec.html      # macOS
xdg-open sec.html   # Linux
```

### O que o dashboard mostra

| Aba | Conteúdo |
|---|---|
| **Matrix** | Barras de progresso por categoria (covered/partial/gap) |
| **ATKs** | Lista completa: ID, categoria, severidade, status |
| **Next Rounds** | Próximos gaps na fila, ordenados por severity |
| **Endpoints** | Inventário de superfície (do discovery) |
| **Métricas** | JSON: tests count, bundle size, rounds completed, last updated |

### Hero tag (topo)

```
RELATÓRIO INICIADO · 2026-06-07 · v0.42 · round 27 completed
```

Atualiza a cada round mergeado. **Recarregue a página** pra ver
atualização (ou deixe F5 a cada minuto).

---

## 6. Parar / pausar / retomar

### Parar

`Ctrl+C` no terminal Claude Code. O **último round commitado fica intacto**.
Rounds em andamento que não foram mergeados ficam como branches `sec/*`
abertas — você decide se mergeia manual ou deleta.

### Pausar (sem parar)

Não existe nativo. O equivalente: pause aceitação de PRs no GitHub e o
skill vai bater no gate "CI ainda não verde" e ficar esperando.

### Retomar

Invoque `blindar` novamente. Ele:
1. Roda Fase 0 (baseline) — encontra `sec.html` existente
2. Pula bootstrap (Fase 2 — reusa o `sec.html`)
3. Continua a Fase 3 do próximo gap não-coberto

Schema do `sec.html` é estável entre rodadas. Pode retomar quantas vezes
quiser.

---

## 7. Quando o skill termina

Para automaticamente quando **TODAS** as condições são verdadeiras:

- [ ] 0 confirmed `crit` no último adversarial review
- [ ] ≤ 2 confirmed `high` (registrados em `.accept-risk.md`)
- [ ] Categorias críticas (web_api, auth, supply_chain, infra, compliance,
      resilience) com ≥ 80% covered+partial
- [ ] 3 runbooks gerados em `docs/`: `incident-response.md`,
      `key-rotation.md`, `supply-chain.md`
- [ ] CI verde por 3 PRs consecutivos
- [ ] Production checklist (Fase 5): todos os gates `bloqueia: sim` ✓

Quando termina, abre PR final com sumário e te avisa no terminal.

---

## 8. Casos especiais

### Projeto BR (LGPD)

Discovery detecta sinais (CPF, CEP, idioma PT-BR, `.env BRAZIL`) e ativa
automaticamente o agente
[`agents/compliance-lgpd-br.md`](agents/compliance-lgpd-br.md). Cria:

- 6 endpoints `/api/lgpd/*` (Art. 18)
- Pasta `docs/lgpd/` com base legal, RIPD, política de privacidade, runbook 72h
- Banner de consentimento granular
- Gate Art. 14 (menores)
- Categoria `compliance_br` no `sec.html`

### Projeto que processa cartão (PCI-DSS)

Discovery detecta (Stripe, MercadoPago, schema com `card_number`, etc.) e
adiciona gates extras da Fase 5. Ver
[`frameworks/pci-dss.md`](frameworks/pci-dss.md).

### Projeto que quer perseguir framework específico

Crie no projeto um arquivo `.compliance-target` com uma das opções:

```
iso27001
nist-csf
cis
asvs-l2
asvs-l3
soc2
pci-dss
```

O skill adapta priorização e gera coverage report no relatório final.

### Stack obscura

O skill tenta categorias genéricas. Funciona, mas perde adaptação fina.
Adicione sua stack em [`stacks.md`](stacks.md) (PR no repo do skill) com
2-3 ATKs específicos pra stack.

### Pentest externo

`agents/pentest.md` cobre SAST/DAST/SCA/fuzz automatizados. Pra pentest
humano (red team), ver [`runbooks/pentest-schedule.md`](runbooks/pentest-schedule.md).

⚠ Integração opcional com [HexStrike AI](https://github.com/0x4m4/hexstrike-ai)
documentada em `agents/pentest.md` — **requer autorização escrita
explícita**, ambiente isolado. Não roda por default.

---

## 9. Rodar em outras AIs

Documentação completa em [`MULTI-AI.md`](MULTI-AI.md).

Resumão:

1. Cole `SKILL.md` + `pipeline/00-baseline.md` no chat
2. Peça: "Atue como agente Baseline do blindar. JSON do schema."
3. Repita pra cada fase, **um agente por turno**, contexto isolado
4. Em adversarial review (Fase 4), 4 turnos separados — 1 por lens
5. Você executa Bash/git/gh; AI escreve os comandos

| AI | Velocidade relativa | Paralelo real? |
|---|---|---|
| Claude Code | 1x (referência) | ✅ Workflow API |
| Claude.ai web | 3-5x mais lento | ❌ |
| ChatGPT | 3-5x mais lento | ❌ |
| Gemini | 3-5x mais lento | ❌ |
| Cursor/Windsurf | 2-3x mais lento | parcial |

**Funcionalmente equivalente** em qualquer AI — só mais lento fora do
Claude Code.

---

## 10. Atualização do skill

### Auto-check (lazy, automático)

A Fase 0 (baseline) roda `scripts/check-update.ps1 -Quiet` em background.
TTL de 24h. Se versão nova existir, imprime aviso uma vez:

```
  blindar v0.5.0 disponivel
  Voce esta em v0.4.1
  Atualizar: git -C "C:\Users\user\.claude\skills\blindar" pull --ff-only
  CHANGELOG: https://github.com/pretinhuu1-boop/blindar/blob/main/CHANGELOG.md
```

### Forçar checagem

```powershell
& "$env:USERPROFILE\.claude\skills\blindar\scripts\check-update.ps1" -Force
```

### Atualizar

Se você clonou via git:

```powershell
git -C "$env:USERPROFILE\.claude\skills\blindar" pull --ff-only
```

Se baixou via tarball (sem `.git`): roda `install.ps1` de novo.

### Desativar auto-check

```powershell
$env:BLINDAR_SKIP_UPDATE_CHECK = "1"
```

(persistente: adicionar no perfil do PowerShell)

---

## 11. Troubleshooting

### "Skill não aparece em /skills"

- Confirmar local: `Test-Path "$env:USERPROFILE\.claude\skills\blindar\SKILL.md"`
- Reiniciar Claude Code
- Confirmar que o frontmatter YAML do `SKILL.md` está válido (não corrompeu
  na clonagem)

### "Suite vermelha — skill se recusa a rodar"

Resolva os testes primeiro. **Por design**: o skill garante que cada round
deixa a suite verde. Não dá pra fazer isso a partir de vermelho.

### "CI demora e eu pago por isso"

Reduza cadência adversarial: editar `SKILL.md`, mudar "a cada 10 rounds"
pra "a cada 20 rounds" (faz menos reviews intermediárias).

### "Quero que pare antes do critério natural"

`Ctrl+C`. Último commit fica intacto. Você pode resumir manualmente
qualquer hora.

### "Round implementou algo que não combina com a arquitetura"

Reverte o PR (`git revert`), registra a divergência em `.accept-risk.md`
explicando o porquê. Próxima rodada, o skill respeita o que está em
`.accept-risk.md`.

### "sec.html parece ter desincronizado do código"

Não deveria acontecer (PR de cada round atualiza ambos atomicamente). Se
aconteceu: deletar `sec.html` e rodar `blindar` de novo. Bootstrap recria
do estado atual.

### "Workflows do Claude Code falham"

Em outra AI, ver `MULTI-AI.md` pro modo manual. Skill funciona em todas.

---

## 12. Comandos úteis

### Status do skill

```powershell
# Versão instalada
Get-Content "$env:USERPROFILE\.claude\skills\blindar\VERSION"

# Última checagem
Get-Content "$env:USERPROFILE\.claude\skills\blindar\.last-check"

# Caminho completo
$env:USERPROFILE + "\.claude\skills\blindar"
```

### Lista de agentes disponíveis

```powershell
Get-ChildItem "$env:USERPROFILE\.claude\skills\blindar\agents\*.md" | Select-Object Name
```

### Validar instalação

```powershell
# Todos os arquivos críticos
$root = "$env:USERPROFILE\.claude\skills\blindar"
@("SKILL.md", "VERSION", "CHANGELOG.md", "agents", "pipeline", "templates\sec.html") |
  ForEach-Object { "{0,-30} {1}" -f $_, (Test-Path "$root\$_") }
```

### Forçar update remoto

```powershell
git -C "$env:USERPROFILE\.claude\skills\blindar" fetch
git -C "$env:USERPROFILE\.claude\skills\blindar" reset --hard origin/main
```

⚠ Destrutivo — perde customizações locais.

### Limpar cache do auto-update

```powershell
Remove-Item "$env:USERPROFILE\.claude\skills\blindar\.last-check" -ErrorAction SilentlyContinue
```

---

## Resumo de 1 página

```
1. INSTALAR
   git clone https://github.com/pretinhuu1-boop/blindar.git \
       ~/.claude/skills/blindar

2. NO PROJETO-ALVO
   - git status limpo
   - tests verdes
   - CI configurada

3. INVOCAR
   abrir Claude Code, digitar: blindar

4. ACOMPANHAR
   abrir sec.html no browser; ver PRs no GitHub

5. PARAR (se precisar)
   Ctrl+C — último commit fica intacto

6. RESUMIR
   invocar blindar de novo — continua do gap atual

7. TERMINA SOZINHO QUANDO
   0 crit + ≤2 high + categorias críticas ≥80% covered
```

---

Dúvidas que não estão aqui? Abrir issue em
[github.com/pretinhuu1-boop/blindar/issues](https://github.com/pretinhuu1-boop/blindar/issues).
