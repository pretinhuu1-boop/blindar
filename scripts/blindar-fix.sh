#!/usr/bin/env bash
# blindar-fix.sh — killer feature: LLM gera patch + teste + PR pra um finding
#
# Lê um finding de .blindar/results/check-<agent>.json, chama Claude API,
# gera patch unified diff + teste regression (best effort), valida com
# `git apply --check`. Default = DRY-RUN (mostra patch, não aplica).
#
# Uso:
#   bash scripts/blindar-fix.sh --finding-id <agent>:<index> [opts]
#   bash scripts/blindar-fix.sh --auto-all [opts]
#
# Opções:
#   --finding-id <agent>:<index>   Finding alvo (ex: check-mock-killer:0)
#   --auto-all                     Itera todos findings high/crit do run-report
#   --dry-run                      (default) Só mostra patch + explanation
#   --apply                        Cria branch + aplica + commita
#   --branch <name>                Nome da branch (default: blindar-fix/<agent>-<ts>)
#   --pr                           Abre PR via `gh pr create` após --apply
#   --model <id>                   Modelo Claude (default: claude-haiku-4-5-20251001)
#   -h | --help                    Ajuda
#
# Garantias:
#   - NUNCA aplica sem --apply explícito
#   - SEMPRE em branch separada (nunca commit em main/master)
#   - VALIDA patch com `git apply --check` antes de aplicar
#   - Sem ANTHROPIC_API_KEY → skip limpo (exit 0)
#   - Timeout 90s na chamada API

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Descobre layout
if [ -d "$SCRIPT_DIR/../templates/checks" ]; then
  SKILL_DIR="$(dirname "$SCRIPT_DIR")"
elif [ -d "$HOME/.claude/skills/blindar" ]; then
  SKILL_DIR="$HOME/.claude/skills/blindar"
else
  echo "ERRO: não consegui localizar o skill blindar" >&2
  exit 72
fi

PROJECT_DIR="${PWD}"
BLINDAR_DIR="${BLINDAR_DIR:-$PROJECT_DIR/.blindar}"
RESULTS_DIR="$BLINDAR_DIR/results"
RUN_REPORT="$BLINDAR_DIR/run-report.json"

# Cores
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  R=$'\e[31m'; G=$'\e[32m'; Y=$'\e[33m'; B=$'\e[34m'; BOLD=$'\e[1m'; RST=$'\e[0m'
else R=''; G=''; Y=''; B=''; BOLD=''; RST=''; fi

log() { echo "$@" >&2; }
log_info() { log "${B}i${RST} $*"; }
log_pass() { log "${G}v${RST} $*"; }
log_warn() { log "${Y}!${RST} $*"; }
log_fail() { log "${R}x${RST} $*"; }
log_section() { log ""; log "${BOLD}--- $* ---${RST}"; }

# ─── Args ───
FINDING_ID=""
AUTO_ALL=0
APPLY=0
PR=0
BRANCH=""
MODEL="claude-haiku-4-5-20251001"
DRY_RUN=1

show_help() {
  sed -n '2,30p' "$0" | sed 's/^# //; s/^#//'
  exit 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    --finding-id) FINDING_ID="$2"; shift 2 ;;
    --auto-all)   AUTO_ALL=1; shift ;;
    --dry-run)    DRY_RUN=1; APPLY=0; shift ;;
    --apply)      APPLY=1; DRY_RUN=0; shift ;;
    --branch)     BRANCH="$2"; shift 2 ;;
    --pr)         PR=1; shift ;;
    --model)      MODEL="$2"; shift 2 ;;
    -h|--help)    show_help ;;
    *) echo "Arg desconhecido: $1" >&2; exit 64 ;;
  esac
done

# ─── Pré-checks ───
if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
  log_warn "ANTHROPIC_API_KEY ausente — blindar-fix skipped"
  log_info "Defina ANTHROPIC_API_KEY pra usar geração automática de patches"
  exit 0
fi

if ! command -v node >/dev/null 2>&1; then
  log_fail "Node.js 20+ requerido"
  exit 70
fi

if ! command -v curl >/dev/null 2>&1; then
  log_fail "curl requerido"
  exit 70
fi

if ! command -v git >/dev/null 2>&1; then
  log_fail "git requerido"
  exit 70
fi

if [ "$AUTO_ALL" -eq 0 ] && [ -z "$FINDING_ID" ]; then
  log_fail "Use --finding-id <agent>:<index> ou --auto-all"
  exit 64
fi

if [ ! -d "$RESULTS_DIR" ]; then
  log_fail "$RESULTS_DIR não existe. Rode blindar primeiro: bash scripts/blindar-run.sh"
  exit 71
fi

# ─── Helpers ───

# Lê finding JSON dado agent + index. Output: JSON string ou vazio.
read_finding() {
  local agent="$1"; local idx="$2"
  local file="$RESULTS_DIR/${agent}.json"
  [ ! -f "$file" ] && file="$RESULTS_DIR/check-${agent}.json"
  [ ! -f "$file" ] && { log_fail "result não encontrado: $agent"; return 1; }

  node -e "
    try {
      const r = JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));
      const f = (r.findings || [])[parseInt(process.argv[2],10)];
      if (!f) { process.exit(0); }
      console.log(JSON.stringify(f));
    } catch(e) { process.exit(0); }
  " "$file" "$idx"
}

# Lista todos findings high/crit do run-report: linhas "agent:index"
list_high_crit_findings() {
  [ ! -f "$RUN_REPORT" ] && return 0
  node -e "
    const fs=require('fs'), path=require('path');
    try {
      const report = JSON.parse(fs.readFileSync(process.argv[1],'utf8'));
      const dir = process.argv[2];
      (report.results || []).forEach(res => {
        if (res.status !== 'failed') return;
        const agent = res.agent.startsWith('check-') ? res.agent : 'check-' + res.agent;
        const fp = path.join(dir, agent + '.json');
        if (!fs.existsSync(fp)) return;
        try {
          const r = JSON.parse(fs.readFileSync(fp,'utf8'));
          (r.findings || []).forEach((f, i) => {
            if (f.severity === 'high' || f.severity === 'crit') {
              console.log(agent + ':' + i);
            }
          });
        } catch(e) {}
      });
    } catch(e) {}
  " "$RUN_REPORT" "$RESULTS_DIR"
}

# Lê janela de ~200 linhas ao redor da linha do finding
read_file_window() {
  local file="$1"; local line="$2"
  [ ! -f "$file" ] && { echo ""; return; }
  local total
  total=$(wc -l < "$file" 2>/dev/null | tr -d ' ')
  [ -z "$total" ] && total=0
  if [ -z "$line" ] || [ "$line" = "0" ] || [ "$line" = "null" ]; then
    head -c 20000 "$file"
    return
  fi
  local start=$((line - 100))
  local end=$((line + 100))
  [ "$start" -lt 1 ] && start=1
  [ "$end" -gt "$total" ] && end="$total"
  sed -n "${start},${end}p" "$file"
}

# Chama Claude API. Args: $1=system $2=user $3=schema_json
# Output: JSON do tool_use.input (ou vazio se erro)
call_claude() {
  local system="$1"
  local user="$2"
  local schema="$3"
  local tool_def
  tool_def=$(node -e "
    const s = JSON.parse(process.argv[1]);
    const t = {
      name: 'propose_patch',
      description: 'Propõe patch unified diff que resolve o finding',
      input_schema: s
    };
    console.log(JSON.stringify(t));
  " "$schema")

  local payload
  payload=$(node -e "
    const p = {
      model: process.argv[1],
      max_tokens: 4096,
      system: process.argv[2],
      tools: [JSON.parse(process.argv[3])],
      tool_choice: { type: 'tool', name: 'propose_patch' },
      messages: [{ role: 'user', content: process.argv[4] }]
    };
    console.log(JSON.stringify(p));
  " "$MODEL" "$system" "$tool_def" "$user")

  if [ -z "$payload" ]; then
    log_warn "Falha ao montar payload"
    return 1
  fi

  local response
  response=$(curl -sS --max-time 90 https://api.anthropic.com/v1/messages \
    -H "x-api-key: $ANTHROPIC_API_KEY" \
    -H "anthropic-version: 2023-06-01" \
    -H "content-type: application/json" \
    -d "$payload" 2>/dev/null)

  if [ -z "$response" ]; then
    log_warn "API call sem resposta (timeout ou rede)"
    return 1
  fi

  if echo "$response" | grep -q '"type":"error"'; then
    local err
    err=$(echo "$response" | grep -oE '"message":"[^"]*"' | head -1 | sed 's/.*"message":"//;s/"$//')
    log_warn "API error: $err"
    return 1
  fi

  node -e "
    try {
      const r = JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
      const t = (r.content || []).find(c => c.type === 'tool_use');
      if (!t) process.exit(0);
      console.log(JSON.stringify(t.input));
    } catch(e) { process.exit(0); }
  " <<< "$response"
}

# Processa 1 finding (agent:index)
process_finding() {
  local fid="$1"
  local agent="${fid%%:*}"
  local idx="${fid##*:}"

  log_section "Finding: $fid"

  local finding_json
  finding_json=$(read_finding "$agent" "$idx")
  if [ -z "$finding_json" ]; then
    log_fail "Finding não encontrado: $fid"
    return 1
  fi

  local sev msg file line fix
  sev=$(node -e "console.log(JSON.parse(process.argv[1]).severity || '')" "$finding_json")
  msg=$(node -e "console.log(JSON.parse(process.argv[1]).message || '')" "$finding_json")
  file=$(node -e "console.log(JSON.parse(process.argv[1]).file || '')" "$finding_json")
  line=$(node -e "console.log(JSON.parse(process.argv[1]).line || '')" "$finding_json")
  fix=$(node -e "console.log(JSON.parse(process.argv[1]).fix || '')" "$finding_json")

  log_info "Severity: $sev"
  log_info "File:line: $file:$line"
  log_info "Message:  $msg"

  if [ -z "$file" ] || [ ! -f "$file" ]; then
    log_warn "Arquivo do finding inacessível ($file) — skip"
    return 1
  fi

  # Janela do arquivo
  local window
  window=$(read_file_window "$file" "$line")
  if [ -z "$window" ]; then
    log_warn "Não consegui ler janela do arquivo"
    return 1
  fi

  # Monta prompt
  local system_prompt
  system_prompt="Você é um engenheiro corrigindo um finding de auditoria blindar. Gere um patch unified diff mínimo, cirúrgico, que resolva o finding SEM quebrar funcionalidade. Inclua header diff --git e índices a/b. Se possível, sugira um teste de regressão (jest/vitest/pytest). NUNCA inclua comentários explicativos no patch — só código. NUNCA toque arquivos não relacionados."

  local user_content
  user_content=$(cat <<PROMPT
## Finding
Agente: $agent
Severity: $sev
Arquivo: $file
Linha: $line
Mensagem: $msg
Sugestão (do check): $fix

## Conteúdo do arquivo (janela ao redor da linha $line)
\`\`\`
$window
\`\`\`

Gere o patch unified diff que resolve este finding. Output via tool propose_patch.
PROMPT
)

  local schema
  schema='{
    "type": "object",
    "required": ["patch", "explanation"],
    "properties": {
      "patch": {"type": "string", "description": "Unified diff (formato git apply). Vazio se não for possível patch automático."},
      "test": {"type": "string", "description": "Código de teste regression (opcional). Pode ser vazio."},
      "explanation": {"type": "string", "description": "1-2 frases explicando a mudança."},
      "confidence": {"type": "string", "enum": ["low","med","high"]}
    }
  }'

  log_info "Chamando Claude API ($MODEL)..."
  local result
  result=$(call_claude "$system_prompt" "$user_content" "$schema")

  if [ -z "$result" ]; then
    log_fail "API não retornou patch estruturado"
    return 1
  fi

  local patch test_code explanation confidence
  patch=$(node -e "console.log(JSON.parse(process.argv[1]).patch || '')" "$result")
  test_code=$(node -e "console.log(JSON.parse(process.argv[1]).test || '')" "$result")
  explanation=$(node -e "console.log(JSON.parse(process.argv[1]).explanation || '')" "$result")
  confidence=$(node -e "console.log(JSON.parse(process.argv[1]).confidence || 'low')" "$result")

  log_info "Confidence: $confidence"
  log_info "Explanation: $explanation"

  if [ -z "$patch" ]; then
    log_fail "Modelo não conseguiu gerar patch automático pra esse finding"
    return 1
  fi

  # Salva patch num arquivo temporário
  local patch_file
  patch_file=$(mktemp 2>/dev/null || echo "$BLINDAR_DIR/.fix-${agent}-${idx}.patch")
  printf '%s\n' "$patch" > "$patch_file"

  log_section "Patch proposto"
  echo "" >&2
  cat "$patch_file" >&2
  echo "" >&2

  if [ -n "$test_code" ]; then
    log_section "Teste regression (proposto)"
    echo "$test_code" >&2
    echo "" >&2
  fi

  # Valida patch
  log_info "Validando com git apply --check..."
  if ! git apply --check "$patch_file" 2>/dev/null; then
    log_fail "Patch FALHOU validação (git apply --check)"
    git apply --check "$patch_file" 2>&1 | head -10 >&2 || true
    log_warn "Patch salvo em: $patch_file"
    return 1
  fi
  log_pass "Patch valida com git apply --check"

  if [ "$DRY_RUN" -eq 1 ]; then
    log_info ""
    log_info "DRY-RUN: nenhuma mudança aplicada. Use --apply pra criar branch + commit."
    log_info "Patch salvo em: $patch_file"
    return 0
  fi

  # ─── APPLY mode ───
  # Determina branch
  local current_branch ts target_branch
  current_branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "detached")
  ts=$(date -u +%Y%m%d-%H%M%S)
  if [ -n "$BRANCH" ]; then
    target_branch="$BRANCH"
  else
    target_branch="blindar-fix/${agent#check-}-${ts}"
  fi

  # Bloqueia commit em main/master
  case "$target_branch" in
    main|master|develop|production)
      log_fail "Recuso criar/commitar em branch protegida: $target_branch"
      return 1
      ;;
  esac

  log_info "Criando branch: $target_branch (a partir de $current_branch)"
  if ! git checkout -b "$target_branch" 2>/dev/null; then
    # Se já existe, tenta checkout
    if ! git checkout "$target_branch" 2>/dev/null; then
      log_fail "Não consegui criar/usar branch $target_branch"
      return 1
    fi
  fi

  log_info "Aplicando patch..."
  if ! git apply "$patch_file" 2>&1 >&2; then
    log_fail "Patch falhou ao aplicar (estranho — passou no --check)"
    git checkout "$current_branch" 2>/dev/null || true
    return 1
  fi
  log_pass "Patch aplicado"

  # Salva teste regression se houver
  if [ -n "$test_code" ]; then
    local test_dir="tests/blindar-regression"
    mkdir -p "$test_dir" 2>/dev/null || true
    local test_file="$test_dir/fix-${agent#check-}-${idx}-${ts}.txt"
    printf '%s\n' "$test_code" > "$test_file"
    log_info "Teste regression salvo: $test_file"
    git add "$test_file" 2>/dev/null || true
  fi

  # Best-effort: roda testes se houver
  if [ -f "package.json" ] && grep -q '"test"' package.json 2>/dev/null; then
    log_info "Rodando npm test (best effort, timeout 60s)..."
    timeout 60 npm test >/dev/null 2>&1 && log_pass "npm test passou" || log_warn "npm test falhou ou não disponível"
  elif [ -f "pytest.ini" ] || [ -f "pyproject.toml" ]; then
    log_info "Rodando pytest (best effort, timeout 60s)..."
    timeout 60 pytest -x >/dev/null 2>&1 && log_pass "pytest passou" || log_warn "pytest falhou ou não disponível"
  fi

  # Commit
  git add -A 2>/dev/null
  local commit_msg
  commit_msg="fix(blindar): resolve $agent finding #$idx

$msg

Generated by blindar-fix.
Severity: $sev
Confidence: $confidence
Explanation: $explanation"

  if ! git commit -m "$commit_msg" 2>&1 >&2; then
    log_fail "git commit falhou"
    return 1
  fi
  log_pass "Commit criado em $target_branch"

  # PR
  if [ "$PR" -eq 1 ]; then
    if ! command -v gh >/dev/null 2>&1; then
      log_warn "gh CLI não disponível — skip --pr"
    else
      log_info "Abrindo PR via gh..."
      local pr_title="fix(blindar): resolve $agent finding #$idx"
      local pr_body
      pr_body=$(printf 'Auto-generated by blindar-fix.\n\n**Finding:** %s\n**File:** %s:%s\n**Severity:** %s\n**Confidence:** %s\n\n%s\n' \
        "$msg" "$file" "$line" "$sev" "$confidence" "$explanation")
      gh pr create --title "$pr_title" --body "$pr_body" 2>&1 >&2 || log_warn "gh pr create falhou"
    fi
  fi

  return 0
}

# ─── Main ───
log_section "blindar-fix"
log_info "Mode: $([ "$APPLY" -eq 1 ] && echo APPLY || echo DRY-RUN)"
log_info "Project: $PROJECT_DIR"
log_info "Results: $RESULTS_DIR"

if [ "$AUTO_ALL" -eq 1 ]; then
  log_section "auto-all: iterando findings high/crit"
  if [ "$APPLY" -eq 1 ]; then
    log_warn "ATENÇÃO: --auto-all + --apply vai criar múltiplos commits/branches"
  fi
  FINDINGS_LIST=$(list_high_crit_findings)
  if [ -z "$FINDINGS_LIST" ]; then
    log_info "Nenhum finding high/crit encontrado em $RUN_REPORT"
    exit 0
  fi
  N=$(echo "$FINDINGS_LIST" | grep -c .)
  log_info "$N findings high/crit identificados"
  OK=0; FAIL=0
  while IFS= read -r fid; do
    [ -z "$fid" ] && continue
    if process_finding "$fid"; then
      OK=$((OK+1))
    else
      FAIL=$((FAIL+1))
    fi
  done <<< "$FINDINGS_LIST"
  log_section "Resumo auto-all"
  log_info "Sucesso: $OK"
  log_info "Falhou:  $FAIL"
  exit 0
fi

# Single finding
process_finding "$FINDING_ID"
exit $?
