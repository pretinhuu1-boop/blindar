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

## IaC fixes como PRs separados (v0.6.0)

Quando projeto tem Terraform/Pulumi/CDK, skill **abre PR separado**
pra fixes de IaC. Não mistura código de app com mudança de infra.

### Padrões cobertos

- **Security groups deny-by-default** (ver
  [`network-security.md`](network-security.md))
- **DB sem IP público**
- **S3 buckets sem listing público** (presigned URL pra acesso)
- **Encryption at rest habilitado** (RDS, EBS, S3)
- **VPC com subnets pública/privada/data**
- **WAF rules pra OWASP Top 10** (AWS WAF, Cloudflare)
- **CloudTrail/Audit logs habilitados**
- **IAM least-privilege** (não usar AdministratorAccess em prod)

### Estrutura do PR

Branch: `iac/<gap-slug>` (não `sec/*` que é app)
Título: `iac: <descricao>`
Body: diff de plan + impacto (recursos afetados, downtime esperado)
Reviewer: marca @<infra-team> se time tem squad separado

### Gate

Mesmo gate da Fase 3: CI verde (incluindo `terraform plan` sem erro),
revisão manual antes de aplicar (porque IaC vira real ao mergear).

## Output

Cada gate vira um job na CI que **falha o PR em regressão**. Não é
warning, é red build.
