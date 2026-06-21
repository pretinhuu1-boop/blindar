---
name: semgrep
category: core
module: 2
priority: P0
description: |
  SAST profundo via Semgrep CLI. Wrapper que invoca regras OWASP, secrets,
  injection patterns e converte achados para o formato blindar (severity
  mapeada → crit/high/med/low). Complementa o check-security regex-only.
---

# Agent: semgrep

Static Application Security Testing (SAST) com Semgrep CLI real.

## Missão

Detectar vulnerabilidades estruturais que regex simples (check-security)
não pega: data-flow taint, padrões cross-file, regras OWASP completas,
detecção de secrets em código, anti-padrões por framework.

Cobre vetores como SQL injection com sources distantes, SSRF, deserialização
insegura, hardcoded credentials, XXE, path traversal, weak crypto, regex
catastrófico (ReDoS), e dezenas de outros conforme `--config=auto`.

## Quando ativar

- Módulo 2 (Security & Auth) — todo wave de hardening
- Após mudanças em código que toca `req.*`, `process.env`, parsers, queries
- Adversarial review final

## Procedimento

1. Instala semgrep se ausente: `pipx install semgrep` (recomendado) ou
   `brew install semgrep` em macOS.
2. Roda `check-semgrep.sh` no root do projeto.
3. Lê `.blindar/results/check-semgrep.json` — findings com `check_id`,
   path e linha apontam exatamente onde corrigir.
4. Para cada finding `crit`/`high`: aplica patch mínimo + teste regressivo
   (mesmo padrão do agent `security`).

## Configuração

Defaults sensatos via env:

| Var | Default | Notas |
|---|---|---|
| `BLINDAR_SEMGREP_CONFIG` | `auto` | usa registry do Semgrep. Alternativas: `p/security-audit`, `p/owasp-top-ten`, `p/secrets`, ou múltiplos separados por espaço |
| `BLINDAR_SEMGREP_TIMEOUT` | `120` | segundos. Aumente em monorepos grandes |
| `BLINDAR_CHANGED_FILES` | (vazio) | combinado com flag `--only-changed-files` reduz escopo a diff |

## Mapeamento de severity

| Semgrep | Blindar | Gate |
|---|---|---|
| `ERROR` | `crit` | bloqueia (exit 1) |
| `WARNING` | `high` | bloqueia (exit 1) |
| `INFO` | `low` | passa (informacional) |
| outras | `med` | passa (informacional) |

## Anti-padrões

- ❌ **Rodar sem config** (`semgrep` puro sem `--config`) — saída vazia,
  falso senso de segurança. Sempre garantir `--config=auto` mínimo.
- ❌ **Ignorar `low`/`med` em bloco** — alguns INFO são taint sources reais
  que viram crit em outro PR. Revisar antes de descartar.
- ❌ **Rodar em CI sem cache** — registry download a cada run é lento.
  Use `SEMGREP_RULES_CACHE_DIR` em CI.
- ❌ **Misturar com check-security** (regex) e contar duplo — semgrep é
  superset; manter check-security como gate rápido em pre-commit, semgrep
  no CI/wave de hardening.

## Output esperado

`.blindar/results/check-semgrep.json` com `findings[]` no schema
`blindar/check-result@v1`. Cada finding contém:
`severity, message ("[semgrep:<rule_id>] <msg>"), file, line`.

## Dependências

- `semgrep` (CLI Python) — obrigatório
- `node` OU `jq` — para parse do JSON. Pelo menos um precisa existir.
- `timeout` (coreutils) ou `gtimeout` (macOS Homebrew) — opcional
