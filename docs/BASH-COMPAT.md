# blindar — Compatibilidade com Bash

Status atual: **blindar é compatível com bash 3.2+** (default do macOS).
O grosso dos scripts usa apenas sintaxe POSIX + extensões bash 3.2.

---

## Resumo

| Plataforma             | Bash default      | Status blindar |
| ---------------------- | ----------------- | -------------- |
| macOS (qualquer versão)| 3.2.57 (GPL v2)   | OK (com warn)  |
| Linux (Ubuntu/Debian)  | 5.x               | OK             |
| Linux (Alpine)         | ash (não bash)    | **NÃO suportado** — instalar `bash` |
| Git Bash (Windows)     | 4.4+ ou 5.x       | OK             |
| WSL                    | 5.x               | OK             |

Em runtime, `_lib.sh` detecta `BASH_VERSINFO[0] < 4` e emite **warn** (não fail).
O warn é mostrado uma vez por execução (controlado por `BLINDAR_BASH_WARN_SHOWN`).

---

## Features bash 4+ que blindar **NÃO** usa (mantido proposital)

Auditoria do diretório `templates/checks/` + `scripts/blindar-run.sh` +
`scripts/blindar-evolve.sh` em 2026-06-21:

| Feature                       | Bash min | Encontrado? | Substituto bash 3.2          |
| ----------------------------- | -------- | ----------- | ---------------------------- |
| `${var,,}` / `${var^^}`       | 4.0      | NÃO         | `tr '[:upper:]' '[:lower:]'` |
| `mapfile` / `readarray`       | 4.0      | NÃO         | `while IFS= read -r line`    |
| `declare -A` (assoc arrays)   | 4.0      | NÃO         | Arrays paralelos / case      |
| `[[ -v var ]]`                | 4.2      | NÃO         | `[ -n "${var+set}" ]`        |
| `coproc`                      | 4.0      | NÃO         | Named pipes / `mkfifo`       |
| `local -n` (nameref)          | 4.3      | NÃO         | `eval` / array names         |
| `wait -n`                     | 4.3      | NÃO         | `wait` (espera todos)        |
| `${!prefix*}` (indirect)      | 3.0      | NÃO         | n/a (já é 3.0)               |
| `&>` (combined redirect)      | 4.0*     | NÃO         | `>file 2>&1`                 |

\* `&>` funciona em bash 3.2 mas não é POSIX. blindar usa a forma explícita
`>file 2>&1` por convenção.

`declare -a NAME=()` (array indexado) é bash 3.2+ — em uso em:
- `templates/checks/_lib.sh:30` — `FINDINGS=()`
- `templates/checks/check-strategic-scanner.sh:12`
- `templates/checks/check-wave-guardian.sh:62`
- `scripts/preflight.sh:19`
- `scripts/blindar-run.sh:120`
- `scripts/blindar-evolve.sh:86`

Todas as instâncias são compatíveis com bash 3.2.

---

## Upgrade de bash no macOS

O bash 3.2 do macOS está congelado desde 2007 (Apple não atualiza por causa
da licença GPL v3 do bash 4+). Recomendado instalar via Homebrew:

```bash
# 1. Instalar bash moderno (5.x)
brew install bash

# 2. Adicionar à lista de shells permitidos
sudo sh -c 'echo /opt/homebrew/bin/bash >> /etc/shells'
# Em Macs Intel, o path é /usr/local/bin/bash
sudo sh -c 'echo /usr/local/bin/bash >> /etc/shells'

# 3. (Opcional) Mudar shell default do user
chsh -s /opt/homebrew/bin/bash

# 4. Verificar
bash --version
# GNU bash, version 5.2.x ...
```

Não precisa mudar o shell default só pra rodar blindar — basta ter o
binário disponível. blindar usa `#!/usr/bin/env bash`, que pega o primeiro
`bash` no `PATH`. Se Homebrew estiver à frente de `/bin`, o bash 5 é usado
automaticamente.

---

## Por que não fail em bash < 4?

Decisão de design: blindar deve **rodar** em macOS sem setup adicional,
mesmo que algumas features futuras possam quebrar. Falhar hard no início
afastaria usuários que só querem testar.

Se um check específico **precisar** de bash 4+, ele deve checar localmente
e fazer `emit_result "$AGENT" "skipped"` com mensagem clara.

Exemplo de check defensivo:

```bash
if [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
  add_finding "info" "Check requer bash 4+ (você tem $BASH_VERSION). Pulando."
  emit_result "$BLINDAR_AGENT" "skipped"
  exit 0
fi
```

---

## Como auditar novos checks

Antes de mergear um check novo, rode esta busca pra detectar regressões:

```bash
# Patterns bash 4+
grep -rEn '\$\{[a-zA-Z_][a-zA-Z0-9_]*[,\^]' templates/checks/ scripts/
grep -rEn '\b(mapfile|readarray)\b'         templates/checks/ scripts/
grep -rEn 'declare -A'                       templates/checks/ scripts/
grep -rEn '\[\[ -v '                         templates/checks/ scripts/
grep -rEn '\bwait -n\b|\bcoproc\b'           templates/checks/ scripts/
grep -rEn 'local -n '                        templates/checks/ scripts/
```

Se algum match aparecer e o uso for justificado, documente aqui a exceção
e adicione o check defensivo de versão acima.
