# Operação: sincronização, auto-update e origem

> Referência do `blindar`, extraída do `SKILL.md` para não ocupar o
> caminho quente. Carregue quando a etapa exigir.

## Sincronização dev ↔ instalada


Se você desenvolve o blindar num repo separado (ex: `Documents/Axial/Blidar`),
a cópia instalada em `~/.claude/skills/blindar` é um **artefato** — nunca edite
lá. Após qualquer mudança no dev:

```bash
bash scripts/sync-skill.sh          # aplica (copia tracked + remove órfãos + verifica)
bash scripts/sync-skill.sh --check  # só reporta drift (exit 1 se divergiu)
```

O script usa o file-set tracked do git como fonte da verdade e preserva o
estado de runtime da instalada (`.git/`, `.blindar/`, `.last-check`).

## Auto-update


**Passo 0 da sequência mandatória**, uma vez por dia (cache de 24h em
`.last-check`). Roda `scripts/check-update.sh --quiet` — ou `check-update.ps1
-Quiet` no PowerShell.

**Pergunta, não atualiza sozinho.** Exit 10 significa versão nova: mostre local
× nova e deixe o operador decidir. Atualizar sem perguntar troca o código sob os
pés de quem está no meio de um trabalho.

O comando de atualização sai do próprio script, porque depende de como a skill
foi instalada: clone → `git pull --ff-only`; artefato do `sync-skill.sh` (sem
`.git`) → reinstalar pelo `install.sh`. Dizer o comando errado é pior que não
dizer, porque o operador tenta e acha que quebrou.

Sem rede: sai 0 e segue. Falha de checagem **nunca** vira bloqueio nem vira
"está atualizado" — significa apenas que não deu para saber.

Desativar: `BLINDAR_SKIP_UPDATE_CHECK=1`. Forçar: `--force` / `-Force`.

## Para humanos


- [`README.md`](../README.md) — apresentação, instalação, uso
- [`USAGE.md`](../USAGE.md) — guia completo passo-a-passo
- [`CHECKLIST.md`](../CHECKLIST.md) — validação pós-download
- [`MULTI-AI.md`](../MULTI-AI.md) — como rodar em qualquer AI
- [`ROADMAP.md`](../ROADMAP.md) — o que ainda não está pronto, honestamente

## Para AIs (você que está lendo isso)


- [`AI-ENTRYPOINT.md`](../AI-ENTRYPOINT.md) — **leia primeiro**, decision tree
- [`CONTRACT.md`](../CONTRACT.md) — estrutura `.blindar/` no projeto-alvo
- [`schemas/`](../schemas/) — JSON schemas pra output validável
- Estado no projeto-alvo: `.blindar/state.json` (ver CONTRACT.md)

## Origem


Skill extraído de execução real: 118 rounds, 68 ATKs fechados, 24 findings
adversariais fixados. Regras refletem bugs reais que já aconteceram.

Se parece dogmático demais, é porque foi pago em PR-vermelho-mergeado.
