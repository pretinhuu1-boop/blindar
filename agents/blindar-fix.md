---
name: blindar-fix
category: meta
module: 14
priority: P1
description: |
  Killer feature do blindar: pega um finding já reportado por outro agente,
  chama Claude API pra gerar patch unified diff + teste regression + cria
  branch isolada + commit (opcionalmente abre PR). Default sempre dry-run.
  Nunca toca main/master. Valida patch com `git apply --check` antes de aplicar.
---

# Agent: blindar-fix

Materialização: `scripts/blindar-fix.sh` (script standalone) +
`cli/commands/fix.js` (wrapper Node).

## Missão

Fechar o loop `discover → fix → ship`. Outros agentes encontram problemas
(check-mock-killer, check-secrets, check-headers-security, etc.) e gravam
`findings[]` em `.blindar/results/check-<agent>.json`. Esse agente pega 1
finding (ou todos high/crit via `--auto-all`) e produz um patch via LLM,
seguro pra revisão humana.

## Quando usar

- Após `blindar-run.sh` reportar findings high/crit
- Quando o usuário pede "corrige automaticamente o problema X"
- Em pipelines CI noturnos com `--apply --pr` (criar PRs auto pra triagem)
- NÃO usar pra refactors amplos — só pra findings cirúrgicos

## Procedimento

1. **Localizar finding**: lê `.blindar/results/check-<agent>.json` e extrai
   `findings[index]` com campos `severity`, `message`, `file`, `line`, `fix`.

2. **Coletar contexto**: lê janela de ~200 linhas ao redor de `line` no
   arquivo do finding (`sed -n start,end p`). Trunca em 50KB.

3. **Montar prompt**: system + user. System exige patch unified diff mínimo,
   cirúrgico, sem comentários explicativos no patch, sem tocar arquivos
   não relacionados.

4. **Chamar Claude API** via `tool_use` forçado com schema:
   ```json
   {
     "patch": "string (unified diff git apply)",
     "test": "string|null (teste regression)",
     "explanation": "1-2 frases",
     "confidence": "low|med|high"
   }
   ```
   Modelo default: `claude-haiku-4-5-20251001`. Timeout 90s.

5. **Validar patch** com `git apply --check <patch_file>`. Se falhar:
   aborta, mostra erro, mantém patch salvo pra debug humano.

6. **Aplicar** (somente com `--apply`):
   - Cria branch `blindar-fix/<agent>-<timestamp>` (NUNCA main/master)
   - `git apply <patch_file>`
   - Salva teste regression em `tests/blindar-regression/` se gerado
   - Roda `npm test` ou `pytest` best-effort (timeout 60s, falha não bloqueia)
   - `git add -A && git commit -m "fix(blindar): ..."`

7. **PR opcional** (`--pr`): `gh pr create` com title + body explicativo.

## Flags

| Flag | Efeito |
|---|---|
| `--finding-id <agent>:<idx>` | Finding alvo (ex: `check-mock-killer:0`) |
| `--auto-all` | Itera todos findings high/crit do run-report |
| `--dry-run` | (default) Só mostra patch + explanation |
| `--apply` | Cria branch + aplica + commita |
| `--branch <name>` | Override do nome da branch |
| `--pr` | Abre PR via `gh` após apply |
| `--model <id>` | Modelo Claude (default haiku-4-5) |

## Garantias

- **NUNCA aplica sem `--apply` explícito** — default é dry-run
- **SEMPRE em branch separada** — recusa explicitamente main/master/develop/production
- **VALIDA patch** com `git apply --check` ANTES de aplicar
- **Sem ANTHROPIC_API_KEY** → skip limpo (exit 0), nunca quebra pipeline
- **Timeout 90s** na API (não trava CI)
- **Best-effort em testes** — falha de teste não impede commit (humano revisa)

## Anti-padrões

- Aplicar `--apply` sem rodar `--dry-run` primeiro pra revisar o patch
- Usar `--auto-all --apply` sem antes ter rodado `--auto-all --dry-run` pra
  ver quantos PRs vão ser criados
- Confiar no `confidence: "low"` — sempre revisar humano antes de mergear
- Ignorar findings que o modelo retorna `patch: ""` (significa que não dá
  pra fix automático — precisa intervenção humana)
- Rodar em branch main/master direto (recusado pelo script, mas não conte
  com isso — sempre faça checkout numa branch de trabalho antes)
- Pedir pra fixar finding de severity `low` — gasto de tokens; foco em
  high/crit

## Limites

- Patch unified diff só funciona se o arquivo não mudou desde o check.
  Re-rode `blindar-run.sh` se houve commits no meio.
- Findings sem `file:line` (ex: deps audit global) não são fixáveis por
  este agente. Use `check-deps-audit` + `npm audit fix` direto.
- Testes regression são best-effort — modelo pode gerar pseudo-código.
  Sempre revise antes de mergear.

## Integração

- Lê: `.blindar/results/check-*.json`, `.blindar/run-report.json`
- Escreve: `tests/blindar-regression/*.txt`, novo branch git + commit
- Depende: bash 4+, node 20+, curl, git, ANTHROPIC_API_KEY
- Opcional: `gh` CLI (pra `--pr`)
