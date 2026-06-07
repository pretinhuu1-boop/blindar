# Fase 0 — Baseline

**Duração**: ~2 min (paralelo)

## Objetivo

Confirmar que o projeto está em estado mergível antes de começar a blindar.
Detecta stack, mede ponto de partida.

## Execução

Em um único Bash call, paralelo:

- Detectar stack (`package.json`, `requirements.txt`, `go.mod`, `Cargo.toml`, etc.)
- Suite atual (`pytest -q`, `npm test`, `go test ./...`, etc.) → contagem
- Type-check (tsc, mypy, etc.)
- Build size se frontend (kb do bundle)
- Git status (deve estar clean)

## Gate

**Suite vermelha → PARA + reporta.** Não blinda projeto quebrado.

Casos que também param a execução:
- Repo sujo (mudanças não-commitadas)
- Sem CI configurada
- Sem permissão de merge

Em todos: 1 reporte claro do que falta, sem tentar adivinhar.

## Saída

Snapshot do baseline gravado pra comparação no relatório final (Fase 6):

```json
{
  "stack": "python+postgres",
  "tests": 142,
  "type_check": "clean",
  "bundle_kb": null,
  "git_clean": true,
  "ci": "github-actions"
}
```

## Auto-update check (lazy)

Roda em background no início desta fase, com TTL de 24h:

```powershell
& "$PSScriptRoot\..\scripts\check-update.ps1" -Quiet
```

Se versão nova disponível, imprime aviso uma vez:
`⚠ blindar v0.X disponível — ver CHANGELOG.md`

Não bloqueia. Não pergunta. Pode ser desativado com `BLINDAR_SKIP_UPDATE_CHECK=1`.
