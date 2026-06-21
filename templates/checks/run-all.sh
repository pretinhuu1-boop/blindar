#!/usr/bin/env bash
# Orquestrador master de TODOS os checks determinísticos.
# Roda cada check, coleta resultados, falha se algum CRIT/HIGH.
#
# Uso:
#   scripts/blindar/run-all.sh             # roda tudo
#   scripts/blindar/run-all.sh --fast      # só checks rápidos (pre-commit)
#   scripts/blindar/run-all.sh --json      # output JSON puro pra CI
#
# Exit codes:
#   0 = tudo passou
#   1 = algum check falhou
#   2 = aborted por erro de setup

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BLINDAR_DIR="${BLINDAR_DIR:-.blindar}"
RESULTS_DIR="${RESULTS_DIR:-$BLINDAR_DIR/results}"
mkdir -p "$RESULTS_DIR"

# Limpa resultados antigos
rm -f "$RESULTS_DIR"/*.json 2>/dev/null || true

MODE="full"
JSON_ONLY=0
for arg in "$@"; do
  case "$arg" in
    --fast)  MODE="fast" ;;
    --json)  JSON_ONLY=1 ;;
    --help)  echo "Uso: $0 [--fast] [--json]"; exit 0 ;;
  esac
done

# Lista de checks por modo (18 em v0.23)
FULL_CHECKS=(
  check-secrets.sh                    # gitleaks
  check-mock-killer.sh                # console.log + TODO + mock + onClick={}
  check-config-externalization.sh     # URLs hardcoded + .env.example sync
  check-deps-audit.sh                 # npm/pip/go/cargo audit + trivy
  check-prisma-schema.sh              # UUID v7 + audit + tenant_id + BigInt
  check-payments.sh                   # CVV/PAN/webhook signature/money em Float
  check-file-uploads.sh               # multer/SVG sanitize/public bucket
  check-tenant-isolation.sh           # queries sem tenant_id + queryRawUnsafe
  check-auth-premium.sh               # bcrypt/HS256/localStorage token/refresh rotation
  check-network-security.sh           # headers HTTP + CORS + rate limit + CSP
  check-observability.sh              # logger + health endpoints + PII em log
  check-api-design.sh                 # OpenAPI + RFC 7807 + idempotency + webhook
  check-i18n-tz.sh                    # @db.Time + money Float + locales sync
  check-pwa-installable.sh            # manifest + SW + icons 192/512/maskable
  check-responsive-a11y.sh            # <img> sem alt + outline:none + button SVG
  check-process-resilience.sh         # SIGTERM + health + connection pool + unbounded
  check-frontend-performance.sh       # size-limit + next/image + use client + RSC
  check-content-quality.sh            # erro técnico em UI + Tem certeza? + plural
  check-lighthouse.sh                 # Lighthouse CI (Perf/A11y/BP/SEO ≥ 90)
  check-bundle-size.sh                # size-limit (≤ 400KB gzipped)
  check-visual-regression.sh          # Chromatic (Storybook)
  check-scheduled-jobs.sh             # Redlock + watchdog + DLQ
  check-sbom-slsa.sh                  # SBOM + SHA pin + Cosign
  check-ai-llm-safety.sh              # OWASP LLM Top 10
  check-realtime.sh                   # WS auth + rooms multi-tenant
  check-feature-flags.sh              # Flag inline + sistema dedicado
  check-email-deliverability.sh       # DKIM/SPF/DMARC + supressão
  check-cdn-strategy.sh               # Cache + immutable + asset hash
  check-seo-marketing-meta.sh         # sitemap + JSON-LD + canonical
  check-backup-recovery.sh            # PITR + drill + encryption
  check-compliance-lgpd-br.sh         # ANPD + endpoints Art. 18 + DPO
  check-cost-observability.sh         # LLM usage + S3 lifecycle + budget
)

FAST_CHECKS=(
  check-secrets.sh
  check-mock-killer.sh
  check-config-externalization.sh
)

if [ "$MODE" = "fast" ]; then
  CHECKS=("${FAST_CHECKS[@]}")
else
  CHECKS=("${FULL_CHECKS[@]}")
fi

# Cores
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; BOLD='\033[1m'; RESET='\033[0m'
else
  RED=''; GREEN=''; BOLD=''; RESET=''
fi

TOTAL_START=$(date +%s)
PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0
FAILED_CHECKS=()

[ "$JSON_ONLY" -eq 0 ] && echo "${BOLD}═══ blindar checks (mode: $MODE) ═══${RESET}"

for check in "${CHECKS[@]}"; do
  script="$SCRIPT_DIR/$check"
  if [ ! -x "$script" ]; then
    chmod +x "$script" 2>/dev/null || true
  fi
  if [ ! -f "$script" ]; then
    [ "$JSON_ONLY" -eq 0 ] && echo "${RED}MISSING:${RESET} $check"
    continue
  fi

  if [ "$JSON_ONLY" -eq 0 ]; then
    bash "$script" 2>&1 || true
  else
    bash "$script" > /dev/null 2>&1 || true
  fi

  # _lib.sh cria como ${agent}.json onde agent = "check-XYZ"
  result_file="$RESULTS_DIR/${check%.sh}.json"
  if [ -f "$result_file" ]; then
    # jq preferido; fallback grep+sed pra ambientes sem jq (Windows)
    if command -v jq >/dev/null 2>&1; then
      status=$(jq -r '.status' "$result_file" 2>/dev/null || echo "unknown")
    else
      status=$(grep -oE '"status"[[:space:]]*:[[:space:]]*"[a-z]+"' "$result_file" | head -1 | sed -E 's/.*"([a-z]+)".*/\1/')
      [ -z "$status" ] && status="unknown"
    fi
    case "$status" in
      passed)  PASS_COUNT=$((PASS_COUNT+1)) ;;
      failed)  FAIL_COUNT=$((FAIL_COUNT+1)); FAILED_CHECKS+=("$check") ;;
      skipped) SKIP_COUNT=$((SKIP_COUNT+1)) ;;
    esac
  else
    FAIL_COUNT=$((FAIL_COUNT+1))
    FAILED_CHECKS+=("$check (sem result file)")
  fi
done

TOTAL_DURATION=$(( $(date +%s) - TOTAL_START ))

# Aggregate (jq se disponível, senão concatena com Node)
AGGREGATE="$RESULTS_DIR/aggregate.json"

if ! command -v jq >/dev/null 2>&1; then
  # Fallback Node.js: concatena results em um aggregate.json simples
  if command -v node >/dev/null 2>&1; then
    node -e "
      const fs=require('fs'),p=require('path');
      const dir='$RESULTS_DIR';
      const files=fs.readdirSync(dir).filter(f=>f.endsWith('.json')&&f!=='aggregate.json');
      const results=files.map(f=>{try{return JSON.parse(fs.readFileSync(p.join(dir,f),'utf8'))}catch(e){return null}}).filter(Boolean);
      const sev=s=>results.flatMap(r=>r.findings||[]).filter(f=>f.severity===s).length;
      const agg={schema:'blindar/aggregate@v1',ran_at:new Date().toISOString(),duration_sec:$TOTAL_DURATION,total_checks:results.length,passed:results.filter(r=>r.status==='passed').length,failed:results.filter(r=>r.status==='failed').length,skipped:results.filter(r=>r.status==='skipped').length,total_findings:results.reduce((a,r)=>a+(r.findings_count||0),0),findings_by_severity:{crit:sev('crit'),high:sev('high'),med:sev('med'),low:sev('low')},results};
      fs.writeFileSync('$AGGREGATE',JSON.stringify(agg,null,2));
    " 2>/dev/null || echo '{"error":"aggregate failed (node missing)"}' > "$AGGREGATE"
  else
    echo '{"error":"aggregate requires jq or node"}' > "$AGGREGATE"
  fi
else
jq -s '
  {
    schema: "blindar/aggregate@v1",
    ran_at: now | strftime("%Y-%m-%dT%H:%M:%SZ"),
    duration_sec: '"$TOTAL_DURATION"',
    total_checks: length,
    passed: [.[] | select(.status == "passed")] | length,
    failed: [.[] | select(.status == "failed")] | length,
    skipped: [.[] | select(.status == "skipped")] | length,
    total_findings: [.[] | .findings_count // 0] | add,
    findings_by_severity: {
      crit: [.[].findings[]? | select(.severity == "crit")] | length,
      high: [.[].findings[]? | select(.severity == "high")] | length,
      med:  [.[].findings[]? | select(.severity == "med")] | length,
      low:  [.[].findings[]? | select(.severity == "low")] | length
    },
    results: .
  }
' "$RESULTS_DIR"/*.json | jq 'del(.results[] | select(.agent == null))' > "$AGGREGATE" 2>/dev/null || \
  echo '{"error": "aggregate failed"}' > "$AGGREGATE"
fi

if [ "$JSON_ONLY" -eq 1 ]; then
  cat "$AGGREGATE"
  exit $([ "$FAIL_COUNT" -gt 0 ] && echo 1 || echo 0)
fi

echo ""
echo "${BOLD}═══ RESUMO ═══${RESET}"
echo "Duração: ${TOTAL_DURATION}s"
echo "${GREEN}Passed:${RESET}  $PASS_COUNT"
echo "${RED}Failed:${RESET}  $FAIL_COUNT"
echo "Skipped: $SKIP_COUNT"
echo ""

if [ "$FAIL_COUNT" -gt 0 ]; then
  echo "${RED}${BOLD}❌ FALHOU${RESET}"
  echo "Checks que falharam:"
  for f in "${FAILED_CHECKS[@]}"; do
    echo "  • $f"
  done
  echo ""
  echo "Detalhes: cat $AGGREGATE | jq"
  echo "Termination: bash $SCRIPT_DIR/../check-termination.sh"
  exit 1
fi

echo "${GREEN}${BOLD}✅ TUDO PASSOU${RESET}"
exit 0
