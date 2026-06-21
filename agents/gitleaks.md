---
name: gitleaks
category: core
module: 2
priority: P0
description: |
  Secrets detection profissional via Gitleaks — wrapper sobre o binário oficial
  com fallback documentado pra check-secrets-rotation.sh quando ausente. Cobre
  100+ regras (AWS, GCP, Stripe, GitHub, Slack, Twilio, etc.) + history scan
  no repo git. Toda finding é CRIT — secrets nunca são "warning".
---

# Agent: gitleaks

Camada profissional de detecção de secrets. Complementa (não substitui) o
`check-secrets-rotation.sh`, que faz grep manual de ~5 patterns. Gitleaks
cobre 100+ regras curadas + entropy scoring + history scan.

## Quando ativar

- Módulo 2 (security baseline) — sempre roda
- Antes de PR pra main
- Pre-commit hook (modo `--no-git --staged`)
- CI/CD obrigatório

## Diferença vs check-secrets-rotation.sh

| Aspecto | check-secrets-rotation | gitleaks |
|---|---|---|
| Regras | ~5 patterns hardcoded (sk_live, AKIA, ghp_, xox, AIza) | 100+ (AWS, GCP, Stripe, GitHub, Slack, Twilio, JWT, PEM, etc.) |
| Entropy scoring | não | sim (descobre secrets custom) |
| History scan | não | sim (acha secret deletado em commit antigo) |
| Config customizada | não | `.gitleaks.toml` |
| Allowlist | não | `.gitleaksignore` |
| Maintained | manual | comunidade ativa |

**Os dois rodam juntos.** check-secrets-rotation é fallback determinístico
(sem deps); gitleaks é o scanner real. Se gitleaks ausente, fallback cobre
o básico — instalar é fortemente recomendado.

## Instalação

```bash
# macOS
brew install gitleaks

# Linux (binário direto)
curl -sSfL https://raw.githubusercontent.com/gitleaks/gitleaks/master/install.sh | sh

# Docker (CI)
docker run -v $(pwd):/repo zricethezav/gitleaks:latest detect --source=/repo
```

## Configuração opcional

`.gitleaks.toml` (custom rules) ou `.gitleaksignore` (allowlist de findings
conhecidos/false-positive) na raiz do repo são detectados automaticamente.

## Env vars

- `BLINDAR_GITLEAKS_HISTORY=0` — desliga scan de history (default 1). Útil em
  repos enormes onde history scan demora >120s.

## Severidade

**Todo finding = CRIT.** Secrets vazados são sempre crítico — não há gradação.
Mesmo "secret de teste" deve ser rotacionado e movido pra `.env`.

## Anti-padrão

> "Já tenho grep no check-secrets-rotation, não preciso de gitleaks."

Errado. Gitleaks pega:
- Secrets custom via entropy (qualquer token aleatório >4.5 bits)
- Secrets em commit history que foram deletados do working tree
- Patterns de 100+ provedores que você nem sabe que usa (algum lib pode ter
  hardcoded)
- JWTs, PEM keys, connection strings com password

Grep manual pega 5 padrões. Gitleaks pega o resto.
