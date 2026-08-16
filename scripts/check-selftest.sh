#!/usr/bin/env bash
# ─── Gate de auto-teste dos checks determinísticos ───
# Prova que cada check registrado DISPARA num fixture vulnerável (exit≠0) e
# CALA num fixture limpo (exit 0). Sem esse par, "volume de checks" = falsa
# sensação de segurança (ver docs/CHECK-BUGS-AUDIT.md).
#
# Também reporta COBERTURA honesta: quantos dos check-*.sh têm par verificado.
#
# Uso: bash scripts/check-selftest.sh
# Exit 0 = todos os pares registrados corretos. Exit 1 = regressão detectada.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"
CHECKS_DIR="$SKILL_DIR/templates/checks"
FIXTURES_DIR="$SKILL_DIR/tests/fixtures"

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  R=$'\e[31m'; G=$'\e[32m'; Y=$'\e[33m'; B=$'\e[1m'; RST=$'\e[0m'
else R=''; G=''; Y=''; B=''; RST=''; fi

# ─── Registro de pares verificados: "check | fixture_vuln | fixture_limpo" ───
# Adicione uma linha aqui SEMPRE que verificar um check contra fixtures.
# Processo: blindar acha um bug → vira check → vira par aqui (docs/INCIDENT-TO-CHECK.md).
PAIRS=(
  "check-cors-csrf.sh            | project-insecure-api    | project-secure-api"
  "check-rate-limit.sh           | project-insecure-api    | project-secure-api"
  "check-headers-security.sh     | project-insecure-api    | project-secure-api"
  "check-access-control.sh       | project-insecure-api    | project-secure-api"
  "check-mock-killer.sh          | project-with-mocks      | clean-project"
  "check-config-externalization.sh | project-with-secrets | clean-project"
  "check-prototype-pollution.sh  | project-protopoll-bad   | project-protopoll-good"
  "check-client-open-redirect.sh | project-openredir-bad   | project-openredir-good"
  "check-llm-system-prompt-leak.sh | project-sysprompt-bad | project-sysprompt-good"
  "check-prisma-schema.sh        | project-multi-tenant-bad| project-prisma-good"
  "check-homolog-only.sh         | project-dev-leak        | project-homolog"
  "check-api-surface-isolation.sh| project-api-isolation-bad | project-api-isolation-good"
  "check-queue-management.sh     | project-queue-bad       | project-queue-good"
  "check-fallback-resilience.sh  | project-resilience-bad  | project-resilience-good"
  "check-session-timeout-ux.sh   | project-timeout-bad     | project-timeout-good"
  "check-deps-sync.sh            | project-deps-bad        | project-deps-good"
  "check-worker-jobs.sh          | project-worker-bad      | project-worker-good"
  "check-datetime-tz.sh          | project-tz-bad          | project-tz-good"
  "check-entrypoint-cmd.sh       | project-entrypoint-bad  | project-entrypoint-good"
  "check-alembic-health.sh       | project-alembic-bad     | project-alembic-good"
  "check-notnull-no-default.sh   | project-notnull-bad     | project-notnull-good"
  "check-ratelimit-response.sh   | project-ratelimit-bad   | project-ratelimit-good"
  "check-infra-windows.sh        | project-infra-win-bad   | project-infra-win-good"
  "check-cryptography.sh         | project-crypto-bad      | project-crypto-good"
  "check-prompt-injection-defense.sh | project-injection-bad | project-injection-good"
  "check-network-security.sh     | project-insecure-api    | project-secure-api"
  "check-security.sh             | project-security-bad    | project-security-good"
  "check-business-logic.sh       | project-bizlogic-bad    | project-bizlogic-good"
  "check-soft-delete.sh          | project-db-bad          | project-prisma-good"
  "check-audit-log.sh            | project-db-bad          | project-prisma-good"
  "check-runtime-secrets.sh      | project-runsecrets-bad  | project-runsecrets-good"
  "check-secrets-rotation.sh     | project-secretrot-bad   | project-secretrot-good"
  "check-tenant-isolation.sh     | project-tenant-bad      | project-tenant-good"
  "check-pagination.sh           | project-pagination-bad  | project-pagination-good"
  "check-supply-chain.sh         | project-supplychain-bad | project-supplychain-good"
  "check-file-uploads.sh         | project-fileupload-bad  | project-fileupload-good"
  "check-api-design.sh           | project-apidesign-bad   | project-apidesign-good"
  "check-auth-premium.sh         | project-authprem-bad    | project-authprem-good"
  "check-i18n-tz.sh              | project-i18n-bad        | project-i18n-good"
  "check-observability.sh        | project-obs-bad         | project-obs-good"
  "check-feature-flags.sh        | project-flags-bad       | project-flags-good"
  "check-sbom-slsa.sh            | project-sbom-bad        | project-sbom-good"
  "check-redis-patterns.sh       | project-redis-bad       | project-redis-good"
  "check-realtime.sh             | project-realtime-bad    | project-realtime-good"
  "check-payments.sh             | project-payments-bad    | project-payments-good"
  "check-process-resilience.sh   | project-procres-bad     | project-procres-good"
  "check-scheduled-jobs.sh       | project-sched-bad       | project-sched-good"
  "check-backup-recovery.sh      | project-backup-bad      | project-backup-good"
  "check-cdn-strategy.sh         | project-cdn-bad         | project-cdn-good"
  "check-cost-observability.sh   | project-costobs-bad     | project-costobs-good"
  "check-email-deliverability.sh | project-email-bad       | project-email-good"
  "check-seo-marketing-meta.sh   | project-seo-bad         | project-seo-good"
  "check-responsive-a11y.sh      | project-a11y-bad        | project-a11y-good"
  "check-frontend.sh             | project-frontend-bad    | project-frontend-good"
  "check-frontend-performance.sh | project-fperf-bad       | project-fperf-good"
  "check-ai-llm-safety.sh        | project-aisafety-bad    | project-aisafety-good"
  "check-tenant-isolation-tests.sh | project-tenant-bad    | project-tenant-good"
  "check-compliance-lgpd-br.sh   | project-lgpd-bad        | project-lgpd-good"
  "check-govtech-acessibilidade.sh | project-govtech-bad   | project-govtech-good"
  "check-ecom-checkout-conversion.sh | project-ecom-bad    | project-ecom-good"
  "check-fintech-banking-br.sh   | project-fintech-bad     | project-fintech-good"
  "check-healthtech-fhir.sh      | project-healthtech-bad  | project-healthtech-good"
  "check-pii-encryption.sh       | project-pii-bad         | project-pii-good"
  "check-log-ops.sh              | project-logops-bad      | project-logops-good"
  "check-pwa-installable.sh      | project-pwa-bad         | project-pwa-good"
  "check-db-engine-consistency.sh | project-dbdrift-bad    | project-dbdrift-good"
  "check-environment-parity.sh   | project-envparity-bad   | project-envparity-good"
  "check-destructive-migration.sh | project-destrmig-bad   | project-destrmig-good"
  "check-decision-log.sh         | project-adr-bad         | project-adr-good"
  "check-defense-theater.sh      | project-theater-bad     | project-theater-good"
  "check-vps-readiness.sh        | project-vps-bad         | project-vps-good"
  "check-git-hygiene.sh         | project-githyg-bad      | project-githyg-good"
  # blindar-learn:insert (mantenha — scripts/blindar-learn.sh insere novos pares acima desta linha)
)

# Retorna o STATUS canônico do check (passed|failed|skipped), lendo o result JSON.
# blindar agrega por status, não por exit code (checks só-med emitem failed+exit0).
run_status() { # dir check → echo status
  local dir="$1" ck="$2"
  rm -rf "$dir/.blindar"
  ( cd "$dir" && bash "$CHECKS_DIR/$ck" >/dev/null 2>&1 ); local rc=$?
  local rf="$dir/.blindar/results/${ck%.sh}.json" st=""
  [ -f "$rf" ] && st=$(grep -oE '"status"[[:space:]]*:[[:space:]]*"[a-z]+"' "$rf" | head -1 | sed -E 's/.*"([a-z]+)".*/\1/')
  [ -z "$st" ] && { if [ "$rc" -ne 0 ]; then st="failed"; else st="passed"; fi; }
  rm -rf "$dir/.blindar"
  echo "$st"
}

echo "${B}═══ blindar check self-test ═══${RST}"
PASS=0; FAIL=0; FAILED=()
declare -A VERIFIED=()

for row in "${PAIRS[@]}"; do
  IFS='|' read -r ck vuln clean <<< "$row"
  ck=$(echo "$ck" | xargs); vuln=$(echo "$vuln" | xargs); clean=$(echo "$clean" | xargs)
  [ ! -f "$CHECKS_DIR/$ck" ] && { echo "${Y}SKIP${RST} $ck (check ausente)"; continue; }

  local_ok=1
  # 1) dispara no vulnerável → status DEVE ser failed
  if [ -d "$FIXTURES_DIR/$vuln" ]; then
    st=$(run_status "$FIXTURES_DIR/$vuln" "$ck")
    if [ "$st" != "failed" ]; then local_ok=0; reason="não disparou no vulnerável ($vuln, status=$st)"; fi
  else echo "${Y}SKIP${RST} $ck (fixture $vuln ausente)"; continue; fi
  # 2) cala no limpo → status NÃO pode ser failed (passed/skipped ok)
  if [ -d "$FIXTURES_DIR/$clean" ]; then
    st=$(run_status "$FIXTURES_DIR/$clean" "$ck")
    if [ "$st" = "failed" ]; then local_ok=0; reason="falso-positivo no limpo ($clean, status=$st)"; fi
  else echo "${Y}SKIP${RST} $ck (fixture $clean ausente)"; continue; fi

  if [ "$local_ok" -eq 1 ]; then
    echo "${G}✓${RST} $ck  (dispara em $vuln, cala em $clean)"
    PASS=$((PASS+1)); VERIFIED["$ck"]=1
  else
    echo "${R}✗${RST} $ck  — $reason"
    FAIL=$((FAIL+1)); FAILED+=("$ck: $reason")
  fi
done

# ─── Cobertura honesta (só checks GATE-ÁVEIS) ───
# Exclui .api.sh (precisam de LLM) e wrappers de scanner externo (semgrep/trivy/
# osv/gitleaks/etc.) — esses não têm par de fixture determinístico.
# Gate-ável é PROPRIEDADE do check, não nome numa lista. A lista curada anterior
# escondia checks que eram gate-áveis e só não tinham par. Um check entra no
# denominador quando TODAS valem:
#   1. não é .api.sh          (precisa de LLM → sem veredito determinístico)
#   2. emite "failed" em algum caminho  (senão é informativo, não gate)
#   3. não lê estado FORA do projeto ($HOME/$APPDATA → depende da máquina)
#   4. não depende de binário externo além de rg/jq, nem de rede/npx
# Wrappers de scanner externo: o check É a invocação da ferramenta, então sem
# ela instalada não há veredito nenhum — não é questão de faltar fixture.
SCANNER_WRAPPERS='check-(semgrep|trivy|osv-scanner|gitleaks|lighthouse|wave-guardian|secrets|deps-audit)\.sh$'

is_gateable() {
  local f="$1" base
  base=$(basename "$f")
  case "$base" in *.api.sh) return 1 ;; esac              # 1
  echo "$base" | grep -qE "$SCANNER_WRAPPERS" && return 1
  grep -qE 'emit_result[^\n]*"failed"' "$f" || return 1   # 2
  grep -qE '\$HOME|\$\{HOME|\$APPDATA|\$\{APPDATA' "$f" && return 1  # 3
  grep -qE 'npx |curl |wget ' "$f" && return 1            # 4
  return 0
}

TOTAL_CHECKS=0
GATEABLE_LIST=()
while IFS= read -r f; do
  if is_gateable "$f"; then
    TOTAL_CHECKS=$((TOTAL_CHECKS+1))
    GATEABLE_LIST+=("$(basename "$f")")
  fi
done < <(find "$CHECKS_DIR" -maxdepth 1 -name 'check-*.sh' 2>/dev/null | sort)
VERIFIED_N=${#VERIFIED[@]}
PCT=0; [ "$TOTAL_CHECKS" -gt 0 ] && PCT=$(( VERIFIED_N * 100 / TOTAL_CHECKS ))

# Denominador honesto: além dos gate-áveis, reporta o total bruto. A lista de
# exclusão acima é curada à mão, então "100%" sempre foi sobre um subconjunto
# escolhido — dizer os dois números evita que a métrica vire propaganda.
ALL_CHECKS=$(find "$CHECKS_DIR" -maxdepth 1 -name 'check-*.sh' 2>/dev/null | wc -l | xargs)
EXCLUDED=$(( ALL_CHECKS - TOTAL_CHECKS ))
PCT_ALL=0; [ "$ALL_CHECKS" -gt 0 ] && PCT_ALL=$(( VERIFIED_N * 100 / ALL_CHECKS ))

echo ""
echo "${B}── cobertura de fixtures ──${RST}"
echo "Gate-áveis com par verificado: ${VERIFIED_N}/${TOTAL_CHECKS} (${PCT}%)"
echo "Sobre TODOS os checks:         ${VERIFIED_N}/${ALL_CHECKS} (${PCT_ALL}%)  — ${EXCLUDED} excluídos (.api.sh + scanners externos)"
echo "Meta: 100% dos gate-áveis. Cada check novo DEVE entrar em PAIRS antes de mergear."

echo ""
echo "${B}═══ RESUMO ═══${RST}"
echo "${G}Pares OK: $PASS${RST}   ${R}Regressões: $FAIL${RST}"
if [ "$FAIL" -gt 0 ]; then
  echo ""; echo "${R}Regressões:${RST}"
  for f in "${FAILED[@]}"; do echo "  • $f"; done
  exit 1
fi
echo "${G}${B}✓ todos os pares registrados corretos${RST}"
exit 0
