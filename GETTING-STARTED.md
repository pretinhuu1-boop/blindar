# blindar — Getting Started (1 página)

> Audita, blinda e prepara qualquer projeto pra produção. 55 checks determinísticos + 4 wrappers Claude API + wave-guardian.

## Pré-requisitos

| Ferramenta | Por quê | Como instalar |
|---|---|---|
| **bash** | Roda os scripts | Mac/Linux: já tem. Windows: [Git Bash](https://gitforwindows.org/) |
| **Node 20+** | Parsing JSON + CLI | [nodejs.org](https://nodejs.org/) |
| **git** | Repo introspection | [git-scm.com](https://git-scm.com/) |
| ripgrep (opcional) | Buscas mais rápidas | `brew/scoop/apt install ripgrep` (fallback grep automático) |
| jq (opcional) | Parse de report | `brew/scoop/apt install jq` (fallback Node automático) |

## 30 segundos: rodar sem instalar nada

```bash
cd seu-projeto
bash ~/.claude/skills/blindar/scripts/blindar-run.sh --fast
cat .blindar/run-report.json
```

Sai com:
- `0` = GO ✅
- `1` = CONDITIONAL-GO (deferred — Claude precisa rodar playbooks)
- `2` = NO-GO (failed)
- `3` = STRICT-FAIL
- `4` = ERRORED (bug em script)

## 1 minuto: instalar no projeto (CI + hooks + workflow)

```bash
cd seu-projeto
bash ~/.claude/skills/blindar/scripts/install-deterministic-checks.sh
```

Cria:
- `scripts/blindar/*.sh` — checks
- `scripts/blindar-run.sh` — orquestrador
- `.github/workflows/blindar.yml` — CI
- `.blindar/accept-risk.md` — template pra aceitar risks conscientes
- `.husky/pre-commit` + `pre-push` (se Husky existe)

Depois adiciona ao `package.json`:
```json
{
  "scripts": {
    "blindar": "bash scripts/blindar-run.sh",
    "blindar:fast": "bash scripts/blindar-run.sh --fast",
    "blindar:strict": "bash scripts/blindar-run.sh --strict"
  }
}
```

E roda: `npm run blindar:fast`

## Uso via Claude Code (skill)

Em qualquer sessão Claude Code:
```
/blindar
```
Roda o launcher interativo (4 perguntas + menu de 15 módulos). Claude segue o `pipeline/` orquestrado pelo SKILL.md.

## Comandos essenciais

```bash
# Roda tudo
bash ~/.claude/skills/blindar/scripts/blindar-run.sh

# Só módulos críticos (security + tests + mocks + pentest)
bash ~/.claude/skills/blindar/scripts/blindar-run.sh --fast

# Módulos específicos
bash ~/.claude/skills/blindar/scripts/blindar-run.sh --module 2,9,11

# Strict: deferred (playbook não-executado) = fail
bash ~/.claude/skills/blindar/scripts/blindar-run.sh --strict

# JSON puro pra CI
bash ~/.claude/skills/blindar/scripts/blindar-run.sh --json > report.json
```

## Wave-guardian (gate de onda)

Final de cada onda do rounds-loop:
```bash
WAVE_NUMBER=2 \
WAVE_AGENTS="mock-killer,access-control" \
MIN_COVERAGE_PCT=90 \
bash ~/.claude/skills/blindar/templates/checks/check-wave-guardian.sh
```
Lê `.blindar/run-report.json` e bloqueia onda se errored/failed-crit/deferred-sem-playbook. Gera `wave-N-guardian.md`.

## Estrutura de output

```
seu-projeto/
└── .blindar/
    ├── scan.json              # stack detectada (strategic-scanner)
    ├── run-report.json        # último run completo
    ├── wave-N-guardian.md     # gate de cada onda
    ├── accept-risk.md         # riscos aceitos conscientemente
    └── results/
        ├── check-mock-killer.json
        ├── check-cryptography.json
        └── ...
```

## Cobertura

- **55 checks determinísticos** (shell + grep, sem dependência de LLM)
- **4 wrappers Claude API** (architect, adversarial-reviewer, pentest, ai-powered-example) — skipped sem `ANTHROPIC_API_KEY`
- **22 agentes playbook-only** — marcados `deferred` no relatório, exigem Claude executar manualmente
- **Wave-guardian** — bloqueia ondas com gap

## Troubleshooting

| Erro | Causa | Solução |
|---|---|---|
| `bash: command not found` | Sem bash no PATH | Instale Git Bash (Windows) |
| `rg: command not found` em log | rg ausente | OK — usa fallback grep automático |
| `jq: command not found` em log | jq ausente | OK — usa fallback Node automático |
| `MODULE-MAP.json não encontrado` | Path errado | Sempre invoque via `~/.claude/skills/blindar/scripts/blindar-run.sh` |
| `Node.js requerido` | Sem Node | Instale Node 20+ |
| `ANTHROPIC_API_KEY ausente` em wrappers API | Esperado | Defina env ou aceite skip |

## Próximo passo

Após rodar `blindar-run.sh`, abra `.blindar/run-report.json`. Findings por severity ficam em `.blindar/results/check-*.json`.

Pra publicação ao usuário/cliente, gera HTML report:
```bash
node ~/.claude/skills/blindar/cli/bin/blindar.js report
```
