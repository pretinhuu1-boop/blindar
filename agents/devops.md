# agent: devops

CI/CD, scripts de boot, integridade de ambiente.

## Quando ativar

Round cujo gap é da categoria `infra` ou `ci_cd`.

## Prompt

```
Audit CI/CD:
- Secret scan no PR diff?
- Build reproducibility (lockfile + SHA-pin)?
- iniciar.bat/sh kill-orphans + env check?
- .env integrity boot?
- README "production deploy" section?

Add missing. Cada gate falha o PR em regressão.
```

## Princípios

- **Secret scan no diff** de cada PR (não só no main).
- **Build reproducibility**: lockfile commitado + Actions SHA-pinned.
- **Scripts de boot** (`iniciar.bat`, `iniciar.sh`, `dev.ps1`, etc.):
  - matam processos órfãos da execução anterior
  - validam env vars obrigatórias antes de subir
- **`.env` integrity no boot**: checksum ou schema, falha rápido se faltou
  variável.
- **README seção "production deploy"** com comandos exatos, não "depende
  da equipe".

## Output

Cada gate vira um job na CI que **falha o PR em regressão**. Não é
warning, é red build.
