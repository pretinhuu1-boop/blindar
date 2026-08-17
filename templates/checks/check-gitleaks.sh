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
  BLINDAR_MISSING_TOOL="gitleaks"   # sem isto o result sai missing_tool:null
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

# ─── O log dizia "working tree + history"; era só history ───
# `gitleaks detect` num repo git varre os COMMITS. Arquivo no working tree que
# ainda não foi commitado ele não vê. Medido: repo com histórico limpo e uma
# chave em src/config.js sem commit saía `passed`, com o log afirmando que a
# working tree tinha sido varrida.
#
# É o momento mais provável de auditar — antes de commitar — e era exatamente o
# ponto cego. Mesma família do falso negativo do check-secrets: varrer o lugar
# errado e chamar o silêncio de aprovação.
#
# Agora a working tree é SEMPRE varrida; o histórico entra a mais quando há
# `.git`. Os dois relatórios são unidos com dedup por regra+arquivo+linha.
OUT_HIST="${TMPDIR:-/tmp}/gitleaks-hist-$$.json"
trap 'rm -f "$OUT_JSON" "$OUT_HIST"' EXIT

log_info "Modo: working tree (sempre)"
SCAN_CMD=(gitleaks detect --no-git --source . "${SCAN_ARGS[@]}" "${CONFIG_ARGS[@]}")

SCAN_HIST=0
if [ -d ".git" ] && [ "$HISTORY_SCAN" = "1" ]; then
  log_info "Modo: + histórico do git (BLINDAR_GITLEAKS_HISTORY=0 desliga)"
  SCAN_HIST=1
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

# Histórico entra como scan SEPARADO e é unido ao da working tree. Erro aqui não
# apaga o que a working tree já achou: um relatório parcial ainda é sinal, e o RC
# abaixo continua responsável por dizer que o scan não completou.
if [ "$SCAN_HIST" = "1" ]; then
  HIST_CMD=(gitleaks detect --no-banner --report-format json --report-path "$OUT_HIST" "${CONFIG_ARGS[@]}")
  if command -v timeout >/dev/null 2>&1; then timeout 120 "${HIST_CMD[@]}" >/dev/null 2>&1; RC_H=$?
  else "${HIST_CMD[@]}" >/dev/null 2>&1; RC_H=$?; fi
  [ "${RC_H:-0}" -gt 1 ] && [ "$RC" -le 1 ] && RC="$RC_H"
  if [ -s "$OUT_HIST" ] && command -v node >/dev/null 2>&1; then
    node -e '
      const fs = require("fs");
      const ler = (p) => { try { const j = JSON.parse(fs.readFileSync(p, "utf8") || "[]");
                                 return Array.isArray(j) ? j : []; } catch (e) { return []; } };
      const vistos = new Set(), saida = [];
      for (const l of [...ler(process.argv[1]), ...ler(process.argv[2])]) {
        const k = [l.RuleID, l.File, l.StartLine].join("::");
        if (vistos.has(k)) continue;
        vistos.add(k); saida.push(l);
      }
      fs.writeFileSync(process.argv[1], JSON.stringify(saida));
    ' "$OUT_JSON" "$OUT_HIST" 2>/dev/null
  fi
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
