## Padrão de check determinístico (`templates/checks/check-<agente>.sh`)

```bash
#!/usr/bin/env bash
BLINDAR_AGENT="check-<agente>"
source "$(dirname "$0")/_lib.sh"
log_section "Check: <agente>"

# Pré-requisitos (skipped gracioso se ausente)
if ! command -v rg >/dev/null 2>&1; then
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

# Respeitar IGNORE_GLOBS — sempre exclua próprio dir + .git
IGNORE=('!node_modules' '!dist' '!.<NOME>' '!.git' '!**/*.test.*')

# Se --since ativo (BLINDAR_CHANGED_FILES env), pode filtrar pra esses arquivos
if [ -n "${BLINDAR_CHANGED_FILES:-}" ]; then
  log_info "Modo --since: $(echo "$BLINDAR_CHANGED_FILES" | wc -l) arquivos"
  # opcional: limitar busca aos arquivos mudados
fi

# Validação 1
COUNT=$(rg -cE "<pattern>" --type ts "${IGNORE[@]}" 2>/dev/null | wc -l)
[ "$COUNT" -gt 0 ] && add_finding "high" "<mensagem>" "" ""

# Decisão final: crit/high → failed; med/low → passed com warn
CRITS=$(printf '%s\n' "${FINDINGS[@]}" | grep -c '"severity":"crit"' 2>/dev/null || echo 0)
HIGHS=$(printf '%s\n' "${FINDINGS[@]}" | grep -c '"severity":"high"' 2>/dev/null || echo 0)
if [ "$CRITS" -gt 0 ] || [ "$HIGHS" -gt 0 ]; then
  emit_result "$BLINDAR_AGENT" "failed" 1
  exit 1
fi
emit_result "$BLINDAR_AGENT" "passed" 0
```

> **Nota**: a variável global `BLINDAR_AGENT` é convenção do `_lib.sh` — mantenha esse nome literal mesmo em outras skills.

---

## Padrão de wrapper API (`templates/checks/check-<agente>.api.sh`)

```bash
#!/usr/bin/env bash
BLINDAR_AGENT="check-<agente>"
source "$(dirname "$0")/_lib.sh"
source "$(dirname "$0")/_api_wrapper.sh"
log_section "Check: <agente> (Claude API)"

# Coleta evidência (limita tokens — max 50k chars)
EVIDENCE=""
[ -f "README.md" ] && EVIDENCE+="=== README ===\n$(head -c 5000 README.md)\n\n"
[ -f "package.json" ] && EVIDENCE+="=== package.json ===\n$(head -c 3000 package.json)\n\n"

[ -z "$EVIDENCE" ] && { emit_result "$BLINDAR_AGENT" "skipped" 0; exit 0; }

SYSTEM="Você é o agente <agente> do <NOME>.
<Instruções específicas: o que procurar, como julgar, anti-padrões.>"

api_check "$BLINDAR_AGENT" "$SYSTEM" "$EVIDENCE"
```

---

## Padrão de wrapper de scanner externo (`templates/checks/check-<scanner>.sh`)

Pra integrar Semgrep, OSV-Scanner, Trivy, Gitleaks, ou similar.

```bash
#!/usr/bin/env bash
BLINDAR_AGENT="check-<scanner>"
source "$(dirname "$0")/_lib.sh"
log_section "Check: <scanner>"

# 1. Skip gracioso se binary ausente (NUNCA fail por ferramenta opcional)
if ! command -v <scanner-bin> >/dev/null 2>&1; then
  log_warn "<scanner> não instalado — skipped"
  log_info "Instale: brew install <scanner> OU pipx install <scanner>"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

# 2. Roda scanner com timeout configurável
TIMEOUT="${BLINDAR_<SCANNER>_TIMEOUT:-120}"
TMP=$(mktemp)
if command -v timeout >/dev/null 2>&1; then
  timeout "${TIMEOUT}s" <scanner-bin> --format=json --output="$TMP" . 2>/dev/null
else
  <scanner-bin> --format=json --output="$TMP" . 2>/dev/null
fi

# 3. Parse JSON via Node (jq fallback) + mapeia severity → blindar
node -e "
  const r = JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));
  (r.results || []).forEach(f => {
    const sevMap = {CRITICAL:'crit', HIGH:'high', MEDIUM:'med', LOW:'low'};
    const sev = sevMap[f.severity] || 'med';
    console.log([sev, f.message, f.file || '', f.line || ''].join('\t'));
  });
" "$TMP" 2>/dev/null | while IFS=$'\t' read -r sev msg file line; do
  add_finding "$sev" "[<scanner>:$id] $msg" "$file" "$line"
done

# 4. Gate: crit/high → failed
CRITS=$(printf '%s\n' "${FINDINGS[@]}" | grep -c '"severity":"crit"' 2>/dev/null || echo 0)
HIGHS=$(printf '%s\n' "${FINDINGS[@]}" | grep -c '"severity":"high"' 2>/dev/null || echo 0)
if [ "$CRITS" -gt 0 ] || [ "$HIGHS" -gt 0 ]; then
  emit_result "$BLINDAR_AGENT" "failed" 1
  rm -f "$TMP"; exit 1
fi
emit_result "$BLINDAR_AGENT" "passed" 0
rm -f "$TMP"
```

**Scanners reais já validados** (usar como referência):
- Semgrep (SAST): `semgrep --config=auto --json`
- OSV-Scanner (SCA): `osv-scanner --format=json --recursive .`
- Trivy (multi): `trivy fs --format=json --scanners vuln,secret,misconfig .`
- Gitleaks (secrets): `gitleaks detect --no-banner --report-format json`

---

