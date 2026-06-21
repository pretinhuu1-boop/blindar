# blindar dashboard (local)

Dashboard HTML estático que lê `.blindar/report.json` e mostra findings.

## Uso

```bash
# 1. Gere o report JSON
npx blindar check --json > .blindar/report.json

# 2. Copie o dashboard pro projeto
cp ~/.claude/skills/blindar/templates/dashboard/dashboard.html .blindar/

# 3. Sirva localmente (qualquer estático serve)
cd .blindar && python -m http.server 8000
# ou
npx http-server .blindar -p 8000

# 4. Abra http://localhost:8000/dashboard.html
```

Sem build, sem deps. Só HTML+CSS+JS vanilla.
Pra produção, integre num app já existente ou sirva via GitHub Pages do repo.
