#!/usr/bin/env bash
# blindar API wrapper — biblioteca pra check-X.api.sh
# Usage:
#   source "$(dirname "$0")/_lib.sh"
#   source "$(dirname "$0")/_api_wrapper.sh"
#   blindar_api_check "agent-name" "system prompt" "user content" "schema"

# ───────────────────────────────────────────────────────────────
# blindar_api_check AGENT_NAME SYSTEM_PROMPT USER_CONTENT [MODEL]
# Chama Claude API com tool_use forçando JSON. Sempre retorna estruturado.
# Exit 0 sempre — findings ficam no result.json com severity.
# ───────────────────────────────────────────────────────────────
blindar_api_check() {
  local agent="$1"
  local system="$2"
  local content="$3"
  local model="${4:-claude-haiku-4-5-20251001}"

  if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
    log_warn "ANTHROPIC_API_KEY ausente — agente $agent skipped"
    add_finding "low" "API check skipped: ANTHROPIC_API_KEY ausente" "" ""
    emit_result "$agent" "skipped" 0
    return 0
  fi

  if ! command -v curl >/dev/null 2>&1; then
    log_warn "curl ausente — skipped"
    emit_result "$agent" "skipped" 0
    return 0
  fi

  local payload tool_def
  tool_def='{
    "name": "report_findings",
    "description": "Reporta findings deste agente em formato estruturado",
    "input_schema": {
      "type": "object",
      "required": ["overall_severity", "findings"],
      "properties": {
        "overall_severity": {"type": "string", "enum": ["none","low","med","high","crit"]},
        "findings": {
          "type": "array",
          "items": {
            "type": "object",
            "required": ["severity","message"],
            "properties": {
              "severity": {"type":"string","enum":["low","med","high","crit"]},
              "message": {"type":"string"},
              "file": {"type":"string"},
              "line": {"type":"integer"},
              "fix": {"type":"string"}
            }
          }
        }
      }
    }
  }'

  # Truncate content pra economizar token (max 50k chars)
  local truncated_content
  truncated_content=$(echo "$content" | head -c 50000)

  payload=$(node -e "
    const p = {
      model: '$model',
      max_tokens: 4096,
      system: process.argv[1],
      tools: [JSON.parse(process.argv[2])],
      tool_choice: {type: 'tool', name: 'report_findings'},
      messages: [{role: 'user', content: process.argv[3]}]
    };
    console.log(JSON.stringify(p));
  " "$system" "$tool_def" "$truncated_content" 2>/dev/null)

  if [ -z "$payload" ]; then
    log_warn "Falha ao montar payload"
    emit_result "$agent" "skipped" 0
    return 0
  fi

  local response
  response=$(curl -sS --max-time 60 https://api.anthropic.com/v1/messages \
    -H "x-api-key: $ANTHROPIC_API_KEY" \
    -H "anthropic-version: 2023-06-01" \
    -H "content-type: application/json" \
    -d "$payload" 2>/dev/null)

  if [ -z "$response" ]; then
    log_warn "API call falhou (sem resposta)"
    add_finding "low" "API call não retornou — verifique conexão e API key" "" ""
    emit_result "$agent" "skipped" 0
    return 0
  fi

  # Detecta erro da API
  if echo "$response" | grep -q '"type":"error"'; then
    local err_msg
    err_msg=$(echo "$response" | grep -oE '"message":"[^"]*"' | head -1 | sed 's/.*"message":"//;s/"$//')
    log_warn "API error: $err_msg"
    add_finding "low" "API error: $err_msg" "" ""
    emit_result "$agent" "skipped" 0
    return 0
  fi

  # Extrai tool_use input (estruturado)
  local result_json
  result_json=$(node -e "
    try {
      const r = JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
      const toolUse = (r.content || []).find(c => c.type === 'tool_use');
      if (!toolUse) { process.exit(0); }
      console.log(JSON.stringify(toolUse.input));
    } catch(e) { process.exit(0); }
  " <<< "$response" 2>/dev/null)

  if [ -z "$result_json" ]; then
    log_warn "API não retornou tool_use estruturado"
    emit_result "$agent" "skipped" 0
    return 0
  fi

  # Parse findings e adiciona via add_finding
  local n_findings
  n_findings=$(node -e "
    try {
      const r = JSON.parse(process.argv[1]);
      console.log(r.findings.length);
    } catch(e) { console.log(0); }
  " "$result_json")

  local has_crit_or_high=0
  local i=0
  while [ "$i" -lt "$n_findings" ]; do
    local sev msg file line
    sev=$(node -e "console.log(JSON.parse(process.argv[1]).findings[$i].severity)" "$result_json" 2>/dev/null)
    msg=$(node -e "console.log(JSON.parse(process.argv[1]).findings[$i].message)" "$result_json" 2>/dev/null)
    file=$(node -e "console.log(JSON.parse(process.argv[1]).findings[$i].file || '')" "$result_json" 2>/dev/null)
    line=$(node -e "console.log(JSON.parse(process.argv[1]).findings[$i].line || '')" "$result_json" 2>/dev/null)
    add_finding "$sev" "[AI] $msg" "$file" "$line"
    [ "$sev" = "crit" ] || [ "$sev" = "high" ] && has_crit_or_high=1
    i=$((i+1))
  done

  if [ "$has_crit_or_high" -eq 1 ]; then
    emit_result "$agent" "failed" 1
    return 0
  fi

  emit_result "$agent" "passed" 0
}

# Helper: lê arquivos relevantes pra um agente (limita tokens)
blindar_collect_evidence() {
  local agent="$1"
  shift
  local files=("$@")
  local out=""
  for f in "${files[@]}"; do
    if [ -f "$f" ]; then
      out+=$'\n\n=== '"$f"' ===\n'
      out+=$(head -c 5000 "$f" 2>/dev/null)
    fi
  done
  echo "$out"
}
