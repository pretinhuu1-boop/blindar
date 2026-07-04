# Pipeline incidente → check (aprendizado permanente)

> Todo bug real que passou pelos checks e só apareceu rodando vira um **check
> determinístico permanente** com par de fixture. O blindar aprende com cada
> incidente e nunca deixa o mesmo bug passar duas vezes.

Este é o processo que gerou os 8 checks de infra da Fase 4 (deps-sync,
worker-jobs, datetime-tz, entrypoint-cmd, alembic-health, notnull-no-default,
ratelimit-response, infra-windows) — cada um nasceu de um bug real.

## Por que

O diferencial do blindar sobre um LLM é a camada determinística (ground truth).
Ela só tem valor se **crescer com a experiência**. Um bug que quebrou produção
uma vez tem que virar um teste que falha até ser corrigido — em todos os projetos.

## Como (1 comando)

```bash
bash ~/.claude/skills/blindar/scripts/blindar-learn.sh \
  --name minha-deteccao --sev high --desc "o que o bug causa"
```

Isso cria, já verde no gate (com placeholder):

- `templates/checks/check-minha-deteccao.sh` — esqueleto determinístico
- `tests/fixtures/project-minha-deteccao-bad/` — reproduz o incidente (dispara)
- `tests/fixtures/project-minha-deteccao-good/` — estado correto (cala)
- linha em `scripts/check-selftest.sh` (PAIRS)

## Depois (torne real)

1. **Edite o check**: troque `BLINDAR_INCIDENT_MARKER` pelo padrão real que
   reproduz o bug (regex/AST/comando). Se exige julgamento (não regex), use
   `.api.sh` em vez de `.sh`.
2. **Edite as fixtures**: `-bad` deve conter o código que causou o incidente;
   `-good`, a versão corrigida. **Comentários neutros** — checks keyword-based
   casam palavras em comentários (contaminação — ver docs/CHECK-BUGS-AUDIT.md).
3. **Verifique**: `bash scripts/check-selftest.sh` — o par tem que dar
   dispara-no-bad + cala-no-good. O gate roda com ripgrep real E com fallback grep.
4. **Registre**: adicione o agente ao módulo certo em `pipeline/MODULE-MAP.json`.

## Regra de ouro (gate)

**Nenhum check entra sem par de fixture provando que detecta o que promete.**
Volume sem verificação = falsa sensação de segurança. O `check-selftest.sh`
reporta cobertura honesta (checks com par verificado / total) e falha o CI se
algum par regride.

## Fluxo mental

```
bug em produção/homolog
   → reproduz num fixture -bad
   → check que dispara nele (e cala no -good)
   → entra no gate (check-selftest.sh)
   → CI garante pra sempre, em todo projeto
```
