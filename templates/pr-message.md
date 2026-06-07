# Template — mensagem de PR de round

Estrutura usada em cada round da Fase 3.

## Título

```
sec({categoria}): close ATK-{XXX} — {título curto}
```

Exemplos:
- `sec(auth): close ATK-014 — TOTP reuse window`
- `sec(supply-chain): close ATK-027 — SHA-pin actions/checkout`
- `sec(lgpd): close ATK-041 — DSAR rate limit`

## Body

```markdown
## ATK-{XXX} — {título}

**Severidade**: {crit|high|med|low}
**Vetor**: {descrição curta do ataque}

## Fix

- {bullet 1}
- {bullet 2}
- {bullet 3}

LOC: {≤80}
Arquivos: {≤5}

## Teste

`tests/test_red{XXX}.py` — {3+ assertions}:
- happy: {descrição}
- edge:  {descrição}
- attack: {descrição}

## Guard estático

```bash
{comando grep que falha se a defesa regredir}
```

## sec.html

- ATK-{XXX}: `gap` → `covered`
- Matrix: `{categoria}` recalc
- Version: v{X.Y} → v{X.Y+1}

## Backward compat

{sim/não — se não, explicar contrato novo}
```

## Squash merge

Todos os rounds são `gh pr merge --squash --delete-branch`.

Branch: `sec/{round-id}-{slug}`. Ex: `sec/r042-totp-reuse`.
