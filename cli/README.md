# blindar — CLI

CLI standalone do skill blindar. Roda os checks determinísticos em
qualquer projeto, sem precisar do Claude Code.

## Instalação

### Via npx (sem instalar globalmente)

```bash
cd seu-projeto
npx blindar init        # instala scripts/blindar/ + CI
npx blindar check       # roda checks
npx blindar terminate   # decisão de release
npx blindar report      # gera HTML
```

### Global

```bash
npm install -g blindar
blindar --version
```

### Pré-requisitos

- **Node.js >= 20**
- **Bash** (Git Bash no Windows, nativo Linux/macOS)
- **ripgrep (`rg`)** — `brew install ripgrep` ou `apt install ripgrep`
- **jq** — JSON processor
- **gitleaks** (recomendado) — `brew install gitleaks`

## Comandos

| Comando | O que faz |
|---|---|
| `blindar check` | Roda todos os 18 checks |
| `blindar check --fast` | Subset rápido (secrets + mock + config) — ≤ 5s |
| `blindar check --json` | Output JSON puro pra CI |
| `blindar init` | Instala scripts/blindar/ + workflow + Husky hooks no projeto |
| `blindar init --force` | Sobrescreve arquivos existentes |
| `blindar terminate` | Decisão matemática release-ready (exit 0-4) |
| `blindar report` | Gera execution-report.html + client-report.html |
| `blindar version` | Mostra versão CLI + skill |
| `blindar help` | Lista comandos |

## Workflow típico

```bash
# 1. Setup inicial
cd meu-projeto
npx blindar init

# 2. Diariamente
npm run blindar:fast    # pre-commit

# 3. Antes de PR
npx blindar check
npx blindar terminate   # 0 = pronto, 1-4 = bloqueia

# 4. Pra cliente
npx blindar report      # HTML com resumo de benefícios
```

## Como integrar em CI

`init` copia automaticamente `.github/workflows/blindar.yml` que roda
em todo PR/push. Configure no GitHub:

```
Settings → Branches → main → Branch protection:
  ☑ Require status checks: blindar-checks
```

Merge **impossível** sem CI verde.

## Status codes (CI-friendly)

| Exit | Significado |
|---|---|
| 0 | Tudo passou |
| 1 | Algum check failed (crit/high) |
| 2 | Erro de setup (missing dep, etc.) |
| 127 | `bash` não encontrado (Windows sem Git Bash) |

`terminate` retorna 1-4 conforme critério violado (veja
`templates/checks/check-termination.sh`).

## Arquitetura

```
[CLI Node]              [Shell scripts]
   ↓                       ↓
blindar.js  ──→  spawn bash  ──→  scripts/blindar/run-all.sh
                                  ↓
                                  18 checks individuais
                                  ↓
                                  .blindar/results/*.json
                                  ↓
                                  aggregate.json
                                  ↓
                                  check-termination.sh
```

CLI Node é fino wrapper. Shell scripts fazem o trabalho real (cross-
platform, sem dependência de Node nas operações). CLI Node só:
- Resolve paths (skill installation, project cwd)
- Parse args com mri
- Output colorido com kleur
- Wraps spawn de bash

## Por que bash?

- **Determinístico**: mesma versão = mesmo resultado
- **CI-native**: GitHub Actions / GitLab / Jenkins rodam shell
- **Sem dependência circular**: não precisa de Node pra rodar checks
- **Auditável**: scripts são código aberto que operador lê

Node CLI é só camada de **conveniência** — `npx blindar check` é mais
amigável que `bash ~/.claude/skills/blindar/templates/checks/run-all.sh`.

## Próximas versões

- v0.25: integração Lighthouse + size-limit + Chromatic
- v0.26: test suite com fixtures (validação do próprio blindar)
- v0.27: standalone binary (sem Node) via `pkg` ou `bun build`
