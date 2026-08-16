## `_lib.sh` — biblioteca base (esqueleto obrigatório)

```bash
#!/usr/bin/env bash
# Source no início de cada check: source "$(dirname "$0")/_lib.sh"

# ─── Bash version warn (não fail) ───
if [ -n "${BASH_VERSION:-}" ] && [ "${BASH_VERSINFO[0]}" -lt 4 ] && [ -z "${BLINDAR_BASH_WARN_SHOWN:-}" ]; then
  echo "⚠ <NOME> testado em bash 4+ (você tem $BASH_VERSION). Veja docs/BASH-COMPAT.md" >&2
  export BLINDAR_BASH_WARN_SHOWN=1
fi

# ─── NÃO usar pipefail/errexit — checks fazem rg|grep|sort pipelines
# onde rg sem match (exit 1) NÃO é erro. Cada check controla local.
set -uo pipefail
set +e +o pipefail

BLINDAR_DIR="${BLINDAR_DIR:-.<NOME>}"
RESULTS_DIR="${RESULTS_DIR:-$BLINDAR_DIR/results}"
mkdir -p "$RESULTS_DIR"

# ─── Cores (CI-aware) ───
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'
  BLUE='\033[0;34m'; BOLD='\033[1m'; RESET='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; BLUE=''; BOLD=''; RESET=''
fi

log_info()    { echo "${BLUE}ℹ${RESET}  $*"; }
log_pass()    { echo "${GREEN}✓${RESET}  $*"; }
log_warn()    { echo "${YELLOW}⚠${RESET}  $*"; }
log_fail()    { echo "${RED}✗${RESET}  $*" >&2; }
log_section() { echo ""; echo "${BOLD}═══ $* ═══${RESET}"; }

declare -a FINDINGS=()

add_finding() {
  local sev="$1"; local msg="$2"; local file="${3:-}"; local line="${4:-}"
  local f=$(printf '{"severity":"%s","message":"%s","file":"%s","line":"%s"}' \
    "$sev" "$(escape_json "$msg")" "$file" "$line")
  FINDINGS+=("$f")
}

escape_json() {
  echo -n "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n'
}

emit_result() {
  local agent="$1"; local status="$2"; local exit_code="${3:-0}"
  local started="${STARTED_AT:-$(date -u +%s)}"
  local duration=$(( $(date -u +%s) - started ))
  local sha=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
  local findings_json="["$(IFS=,; echo "${FINDINGS[*]:-}")"]"

  local out="$RESULTS_DIR/${agent}.json"
  cat > "$out" <<EOF
{
  "schema": "<NS>/check-result@v1",
  "agent": "$agent",
  "ran_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "git_sha": "$sha",
  "status": "$status",
  "exit_code": $exit_code,
  "duration_sec": $duration,
  "findings_count": ${#FINDINGS[@]},
  "findings": $findings_json
}
EOF

  log_info "Resultado: $out"
  case "$status" in
    passed) log_pass "$agent PASSED" ;;
    failed) log_fail "$agent FAILED (${#FINDINGS[@]} findings)" ;;
    skipped) log_warn "$agent SKIPPED" ;;
  esac
}

# ─── rg fallback (grep -rE) quando binário ausente ───
# Detecta via type -P (não pega função do shell). command -v não basta.
if ! type -P rg >/dev/null 2>&1; then
  rg() {
    set +eo pipefail
    local includes=() excludes=() flags=("-rE") pattern="" path="."
    while [ $# -gt 0 ]; do
      case "$1" in
        -n|-E) shift ;;
        -i) flags+=("-i"); shift ;;
        -c) flags+=("-c"); shift ;;
        -nE|-En) shift ;;
        -ni|-in) flags+=("-i"); shift ;;
        -A) flags+=("-A" "$2"); shift 2 ;;
        -B) flags+=("-B" "$2"); shift 2 ;;
        -l|-nl|-ln) flags+=("-l"); shift ;;
        --type)
          case "$2" in
            ts) includes+=(--include='*.ts' --include='*.tsx' --include='*.cts' --include='*.mts') ;;
            js) includes+=(--include='*.js' --include='*.jsx' --include='*.mjs' --include='*.cjs') ;;
            json) includes+=(--include='*.json') ;;
            yml|yaml) includes+=(--include='*.yml' --include='*.yaml') ;;
            html) includes+=(--include='*.html') ;;
            md) includes+=(--include='*.md') ;;
            env) includes+=(--include='.env*') ;;
          esac
          shift 2 ;;
        '!'*)
          local p="${1#!}"
          [[ "$p" == \*\*/* ]] && p="${p#\*\*/}"
          [[ "$p" == */\*\* ]] && p="${p%/\*\*}"
          if [[ "$p" == *\** ]]; then
            excludes+=(--exclude="${p##*/}")
          else
            excludes+=(--exclude-dir="$p")
          fi
          shift ;;
        --) shift ;;
        -*) shift ;;
        *)
          if [ -z "$pattern" ]; then pattern="$1"
          else path="$1"; fi
          shift ;;
      esac
    done
    [ -z "$pattern" ] && return 0
    grep "${flags[@]}" "${includes[@]}" "${excludes[@]}" -- "$pattern" "$path" 2>/dev/null
    local rc=$?
    [ $rc -eq 1 ] && return 0
    return $rc
  }
  export -f rg
fi

# ─── Detecção de stack helpers ───
has_file() { [ -f "$1" ]; }
has_dir()  { [ -d "$1" ]; }
is_nodejs()  { has_file "package.json"; }
is_python()  { has_file "pyproject.toml" || has_file "requirements.txt"; }
is_go()      { has_file "go.mod"; }
is_rust()    { has_file "Cargo.toml"; }
is_prisma()  { has_file "prisma/schema.prisma"; }
is_nextjs()  { has_file "next.config.js" || has_file "next.config.ts" || has_file "next.config.mjs"; }

STARTED_AT=$(date -u +%s)

# ─── NOTA: NÃO usar `trap ERR` aqui ───
# trap ERR só dispara com errexit ativo (set -e). Como esta lib desliga
# errexit acima, trap ERR seria código morto. Cada check gerencia seus
# erros via emit_result + add_finding.
```

---

## `_api_wrapper.sh` — wrapper Claude API (esqueleto obrigatório)

```bash
#!/usr/bin/env bash
# Usage em check-X.api.sh:
#   source "$(dirname "$0")/_lib.sh"
#   source "$(dirname "$0")/_api_wrapper.sh"
#   api_check "agent" "system prompt" "user content"

api_check() {
  local agent="$1"
  local system="$2"
  local content="$3"
  local model="${4:-claude-haiku-4-5-20251001}"

  if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
    log_warn "ANTHROPIC_API_KEY ausente — agente $agent skipped"
    emit_result "$agent" "skipped" 0
    return 0
  fi

  if ! command -v curl >/dev/null 2>&1; then
    emit_result "$agent" "skipped" 0
    return 0
  fi

  local tool_def='{
    "name": "report_findings",
    "description": "Reporta findings em formato estruturado",
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

  local truncated_content
  truncated_content=$(echo "$content" | head -c 50000)

  local payload
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

  [ -z "$payload" ] && { emit_result "$agent" "skipped" 0; return 0; }

  local response
  response=$(curl -sS --max-time 60 https://api.anthropic.com/v1/messages \
    -H "x-api-key: $ANTHROPIC_API_KEY" \
    -H "anthropic-version: 2023-06-01" \
    -H "content-type: application/json" \
    -d "$payload" 2>/dev/null)

  if [ -z "$response" ] || echo "$response" | grep -q '"type":"error"'; then
    log_warn "API error — skipped"
    emit_result "$agent" "skipped" 0
    return 0
  fi

  # Parse com Node 1x — NÃO 4x por finding (performance)
  local parsed
  parsed=$(node -e "
    const r = JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
    const toolUse = (r.content||[]).find(c => c.type === 'tool_use');
    if (!toolUse) { console.log('{}'); process.exit(0); }
    console.log(JSON.stringify(toolUse.input));
  " <<< "$response" 2>/dev/null)

  # Itera findings via Node 1x — extrai tudo numa passada
  local findings_lines
  findings_lines=$(node -e "
    const r = JSON.parse(process.argv[1] || '{}');
    (r.findings || []).forEach(f => {
      const line = [f.severity || 'med', f.message || '', f.file || '', f.line || ''].join('\t');
      console.log(line);
    });
  " "$parsed" 2>/dev/null)

  local has_crit_or_high=0
  while IFS=$'\t' read -r sev msg file line; do
    [ -z "$sev" ] && continue
    add_finding "$sev" "[AI] $msg" "$file" "$line"
    [ "$sev" = "crit" ] || [ "$sev" = "high" ] && has_crit_or_high=1
  done <<< "$findings_lines"

  if [ "$has_crit_or_high" -eq 1 ]; then
    emit_result "$agent" "failed" 1
    return 0
  fi
  emit_result "$agent" "passed" 0
}
```

---

