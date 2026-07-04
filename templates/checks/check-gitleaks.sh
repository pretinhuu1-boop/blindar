#!/usr/bin/env bash
# Materializa: gitleaks (secrets detection profissional)
# Wrapper que invoca gitleaks real (preferido) ou cai pra grep fallback
# do check-secrets-rotation.sh quando binário não instalado.
BLINDAR_AGENT="check-gitleaks"
source "$(dirname "$0")/_lib.sh"
log_section "Check: gitleaks (secrets scanner)"

# 1. Detecta gitleaks
if ! command -v gitleaks >/dev/null 2>&1; then
  log_warn "gitleaks não instalado"
  log_info "Instale: 'brew install gitleaks' ou https://github.com/gitleaks/gitleaks#installing"
  log_info "Fallback: check-secrets-rotation.sh cobre o básico (grep manual de patterns conhecidos)"
  add_finding "low" "gitleaks ausente — instale pra cobertura 100+ regras (vs grep manual). Fallback: check-secrets-rotation.sh" "" ""
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

GITLEAKS_VERSION=$(gitleaks version 2>/dev/null | head -1 || echo "unknown")
log_info "gitleaks detectado: $GITLEAKS_VERSION"

# 2. Detecta config customizada
CONFIG_ARGS=()
if [ -f ".gitleaks.toml" ]; then
  log_info "Usando config customizada: .gitleaks.toml"
  CONFIG_ARGS+=(--config=.gitleaks.toml)
elif [ -f ".gitleaksignore" ]; then
  log_info ".gitleaksignore detectado (aplicado automaticamente pelo gitleaks)"
fi

# 3. Decide modo: history scan (repo git) ou só working tree
OUT_JSON="${TMPDIR:-/tmp}/gitleaks-out-$$.json"
trap 'rm -f "$OUT_JSON"' EXIT

HISTORY_SCAN="${BLINDAR_GITLEAKS_HISTORY:-1}"
SCAN_ARGS=(--no-banner --report-format json --report-path "$OUT_JSON")

if [ -d ".git" ] && [ "$HISTORY_SCAN" = "1" ]; then
  log_info "Modo: repo git — escaneando working tree + history (BLINDAR_GITLEAKS_HISTORY=0 desliga)"
  # detect padrão escaneia history quando há .git
  SCAN_CMD=(gitleaks detect "${SCAN_ARGS[@]}" "${CONFIG_ARGS[@]}")
else
  log_info "Modo: working tree apenas (--no-git)"
  SCAN_CMD=(gitleaks detect --no-git --source . "${SCAN_ARGS[@]}" "${CONFIG_ARGS[@]}")
fi

# 4. Roda com timeout 120s (timeout pode não existir em macOS sem coreutils)
if command -v timeout >/dev/null 2>&1; then
  timeout 120 "${SCAN_CMD[@]}" >/dev/null 2>&1
  RC=$?
elif command -v gtimeout >/dev/null 2>&1; then
  gtimeout 120 "${SCAN_CMD[@]}" >/dev/null 2>&1
  RC=$?
else
  "${SCAN_CMD[@]}" >/dev/null 2>&1
  RC=$?
fi

# gitleaks exit codes: 0=clean, 1=leaks found, outros=erro
if [ $RC -eq 124 ]; then
  add_finding "high" "gitleaks timeout (>120s) — repo grande, considere BLINDAR_GITLEAKS_HISTORY=0" "" ""
  emit_result "$BLINDAR_AGENT" "failed" 124
  exit 1
fi

if [ $RC -ne 0 ] && [ $RC -ne 1 ]; then
  add_finding "med" "gitleaks falhou com exit code $RC (verifique config/permissões)" "" ""
  emit_result "$BLINDAR_AGENT" "failed" "$RC"
  exit 1
fi

# 5. Parse JSON
if [ ! -s "$OUT_JSON" ]; then
  log_pass "gitleaks: nenhum secret detectado"
  emit_result "$BLINDAR_AGENT" "passed" 0
  exit 0
fi

# Parse via python (mais robusto que jq, presente em quase todo sistema)
PARSER=""
if command -v python3 >/dev/null 2>&1; then
  PARSER="python3"
elif command -v python >/dev/null 2>&1; then
  PARSER="python"
fi

if [ -n "$PARSER" ]; then
  COUNT=$("$PARSER" -c "
import json,sys
try:
  with open('$OUT_JSON') as f:
    data = json.load(f)
  if not isinstance(data, list):
    data = []
  for item in data:
    rule = item.get('RuleID', 'unknown')
    desc = item.get('Description', 'secret detected')
    ent = item.get('Entropy', 0)
    file = item.get('File', '')
    line = item.get('StartLine', '')
    # output: rule|desc|entropy|file|line
    print(f'{rule}|{desc}|{ent}|{file}|{line}')
  print(f'__COUNT__{len(data)}', file=sys.stderr)
except Exception as e:
  print(f'__ERR__{e}', file=sys.stderr)
  sys.exit(2)
" 2>&1 1>"$OUT_JSON.parsed")
  PARSE_RC=$?

  if [ $PARSE_RC -ne 0 ]; then
    add_finding "med" "gitleaks JSON parse falhou: $COUNT" "" ""
    emit_result "$BLINDAR_AGENT" "failed" 1
    exit 1
  fi

  TOTAL=0
  while IFS='|' read -r rule desc entropy file line; do
    [ -z "$rule" ] && continue
    add_finding "crit" "[gitleaks:$rule] $desc (entropy=$entropy)" "$file" "$line"
    TOTAL=$((TOTAL + 1))
  done < "$OUT_JSON.parsed"
  rm -f "$OUT_JSON.parsed"
else
  # Fallback grosso sem python — conta linhas com "RuleID"
  TOTAL=$(grep -c '"RuleID"' "$OUT_JSON" 2>/dev/null)
  add_finding "crit" "[gitleaks] $TOTAL secret(s) detectado(s) — instale python pra parse detalhado" "$OUT_JSON" ""
fi

if [ "$TOTAL" -gt 0 ]; then
  log_fail "gitleaks: $TOTAL secret(s) detectado(s) — secrets são sempre CRIT"
  emit_result "$BLINDAR_AGENT" "failed" 1
  exit 1
fi

log_pass "gitleaks: nenhum secret detectado"
emit_result "$BLINDAR_AGENT" "passed" 0
exit 0
