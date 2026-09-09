#!/usr/bin/env bash
# Release gates: agrega .blindar/results/*.json em 11 dimensões independentes e
# emite o veredito GO / CONDITIONAL GO / NO-GO em .blindar/gates.json.
#
# Por que existe: até a v0.52 a decisão de release era "0 crit + ≤2 high". Um
# projeto pode ter 0 crit e 0 high e ainda assim rodar SQLite em produção, sem
# backup restaurável, sem rollback e com mock no caminho crítico. Severidade
# agregada não é a mesma coisa que prontidão — ela mede o que os checks
# ACHARAM, não o que ficou por verificar.
#
# Este script NÃO chama emit_result: é um decisor de release, como o
# check-termination.sh, não a materialização de um agente. Por isso fica fora do
# denominador de cobertura de fixtures do check-selftest.sh (critério 2).
#
# Exit: 0 = GO | 1 = CONDITIONAL GO | 2 = NO-GO | 5 = jq ausente (NO-GO por
# falta de instrumentação, nunca aprovação)

set -uo pipefail

BLINDAR_DIR="${BLINDAR_DIR:-.blindar}"
RESULTS_DIR="$BLINDAR_DIR/results"
GATES_OUT="$BLINDAR_DIR/gates.json"

# Leitor de JSON: Node primeiro (1 processo para o diretório inteiro), jq como
# alternativa. Sem nenhum dos dois não há contagem, e ausência de contagem é
# NO-GO por falta de instrumentação — nunca aprovação.
JSON_READER=""
command -v node >/dev/null 2>&1 && JSON_READER="node"
[ -z "$JSON_READER" ] && command -v jq >/dev/null 2>&1 && JSON_READER="jq"
if [ -z "$JSON_READER" ]; then
  echo "❌ nem 'node' nem 'jq' disponíveis — impossível ler os results." >&2
  echo "   Sem contagem não há veredito, e ausência de veredito é NO-GO," >&2
  echo "   não aprovação." >&2
  echo "   Instale: winget install jqlang.jq | apt install jq | brew install jq" >&2
  exit 5
fi

if [ ! -d "$RESULTS_DIR" ]; then
  echo "❌ $RESULTS_DIR não existe. Rode os checks antes: bash scripts/blindar/run-all.sh" >&2
  exit 2
fi

# ─── Mapa check → gate ───
# Por padrão glob, não lista exaustiva: check novo cai num gate por afinidade de
# nome em vez de sumir. O que não casar aparece em UNMAPPED no relatório — buraco
# de mapeamento vira visível, não silencioso.
#
# Há uma diferença que a v0.80 ainda não fazia: "check que ninguém mapeou" e
# "check que fica fora de propósito" caíam no mesmo balde. Um balde com ruído
# esperado dentro não é lido por ninguém, e foi assim que 18 checks — entre eles
# `check-payments` com crit de PCI, `check-client-bundle-secrets` com segredo no
# bundle e `check-healthtech-fhir` com PHI em log — rodaram, acharam crítico, e
# não chegaram a dimensão nenhuma. Achado que não chega ao veredito é
# exatamente o modo de falha que este arquivo existe para recusar.
#
# Agora são duas listas. `motivo_fora_do_gate()` nomeia quem fica fora e por
# quê; o que sobra em UNMAPPED é buraco, e buraco pesa no veredito.

# ─── Fora do veredito POR DESENHO, com motivo nomeado ───
# Mesmo contrato do motivo_exclusao() do check-selftest.sh: exclusão sem motivo
# escrito é silêncio, e silêncio é onde o bug mora. Quem entrar aqui precisa
# responder "o que cobre isso, então?".
motivo_fora_do_gate() {
  case "$1" in
    check-strategic-scanner)
      echo "Fase 0 — descobre a stack e grava scan.json; sempre passa, nunca emite finding" ;;
    check-mcp-recommended)
      echo "sugere MCP para a stack e não instala nada — a decisão é do operador" ;;
    check-ai-powered-example)
      echo "template de exemplo para escrever check novo, não roda em auditoria" ;;
    check-wave-guardian)
      echo "gate da ONDA, não do projeto — reprova a run (agente errored, playbook pendente) e já bloqueia pelo próprio exit code" ;;
    check-growth-opportunities|check-product-critic|check-proactive-analysis)
      echo "consultivo: o LLM opina sobre produto e oportunidade, e opinião não reprova release — sai no relatório, não no veredito" ;;
    *) echo "" ;;
  esac
}

gate_of() {
  # Excecao declarada vem antes do mapa: quem tem motivo escrito nao disputa gate.
  if [ -n "$(motivo_fora_do_gate "$1")" ]; then echo "OUT_OF_GATE"; return; fi
  case "$1" in
    check-security|check-access-control|check-cryptography|check-secrets*|check-runtime-secrets|\
    check-headers-security|check-cors-csrf|check-rate-limit|check-auth-premium|\
    check-business-logic|check-prototype-pollution|check-client-open-redirect|check-semgrep|\
    check-gitleaks|check-trivy|check-osv-scanner|check-supply-chain|check-sbom-slsa|\
    check-deps-audit|check-network-security|check-tenant-isolation*|check-file-uploads|\
    check-api-surface-isolation|check-mcp-security|check-prompt-injection-defense|\
    check-ai-llm-safety|check-llm-system-prompt-leak|check-vector-db-security|\
    check-fine-tune-data-leak|check-pentest*|check-defense-theater|check-invisible-unicode|\
    check-redteam-origin|check-mfa-readiness|check-prompt-untrusted-delimiting|\
    check-security-headers-completo|check-npm-ci-lockfile|check-image-scan|\
    check-deps-auto-update|check-container-hardening|check-payments|check-client-bundle-secrets|\
    check-git-hygiene|check-fintech-banking-br|check-adversarial-reviewer)
      echo "SECURITY" ;;
    check-api-design|check-architect|check-solution-architect|check-config-externalization|\
    check-feature-flags|check-api-gateway|check-idempotency-keys|check-feature-flags-killswitch)
      echo "ARCHITECTURE" ;;
    check-db-engine-consistency|check-prisma-schema|check-soft-delete|check-notnull-no-default|\
    check-alembic-health|check-pagination|check-audit-log|check-redis-patterns|\
    check-destructive-migration)
      echo "DATABASE" ;;
    check-mock-killer|check-functional-e2e|check-entrypoint-cmd|check-homolog-only|\
    check-infra-windows|check-api-frontend-coverage|check-user-journey-simulator|\
    check-failure-ux|check-negative-control|check-feature-gap-analyzer)
      echo "RUNTIME" ;;
    check-queue-management|check-fallback-resilience|check-process-resilience|check-worker-jobs|\
    check-scheduled-jobs|check-realtime|check-ratelimit-response|check-termination|\
    check-load-test|check-chaos-engineering|check-multi-region|check-chaos-run|check-load-curve|\
    check-graceful-shutdown|check-outbound-queue-readiness|check-horizontal-scale)
      echo "RESILIENCE" ;;
    check-observability|check-log-ops|check-cost-observability|check-observability-present|\
    check-llm-latency-observability|check-synthetic-uptime|check-metered-external-cost-guard)
      echo "OBSERVABILITY" ;;
    check-compliance-lgpd-br|check-pii-encryption|check-log-ops-retention|\
    check-regulatory-mapper|check-pii-in-logs|check-lgpd-transferencia-internacional|\
    check-dsr-automation|check-retention-job-agendado|check-breach-runbook|\
    check-healthtech-fhir)
      echo "PRIVACY" ;;
    check-responsive-a11y|check-frontend*|check-content-quality|check-visual-regression|\
    check-i18n-tz|check-datetime-tz|check-seo-marketing-meta|check-seo-foundation|\
    check-pwa-installable|check-session-timeout-ux|check-lighthouse|check-bundle-size|\
    check-govtech-acessibilidade|check-image-optimization|check-resource-hints|\
    check-a11y-executado|check-geo-readiness|check-ecom-checkout-conversion|check-rag-quality)
      echo "QUALITY" ;;
    check-environment-parity|check-deps-sync|check-cdn-strategy|check-patch-management|\
    check-vps-readiness|check-deploy-identity|check-rollback-ready|check-email-deliverability)
      echo "DEPLOYMENT" ;;
    check-backup-recovery|check-backup-restore-tested)
      echo "BACKUP_RECOVERY" ;;
    check-documentation*|check-runbook*|check-decision-log|check-report-integrity|\
    check-assumption-probe)
      echo "DOCUMENTATION" ;;
    *) echo "UNMAPPED" ;;
  esac
}

GATES="SECURITY ARCHITECTURE DATABASE RUNTIME RESILIENCE OBSERVABILITY PRIVACY QUALITY DEPLOYMENT BACKUP_RECOVERY DOCUMENTATION"

# ─── Dimensões que só fecham com o sistema EXERCITADO ───
# Estas três respondem perguntas que nenhuma leitura de repositório responde:
#   RUNTIME    — o que o código afirma acontece de fato quando roda?
#   RESILIENCE — o que acontece quando uma dependência cai?
#   DEPLOYMENT — o artefato no ar é o que foi auditado?
#
# Nelas, check estático passando prova que a ESTRUTURA existe. Até a v0.78 isso
# virava PASS, e PASS era lido como "verificado". Agora, sem nenhum check
# dinâmico que tenha de fato exercitado o sistema, a dimensão fica NOT EXERCISED:
# um terceiro estado, entre "não rodou nada" e "medi e estava bom".
DYNAMIC_REQUIRED="${BLINDAR_DYNAMIC_REQUIRED:-RUNTIME RESILIENCE DEPLOYMENT}"

# ─── Coleta: uma linha por check ───
# Formato intermediário: agent|status|crit|high|missing_tool. O mapeamento
# check→gate fica só no gate_of() do bash, para não duplicar a regra nos dois
# leitores.
RAW=$(mktemp)
if [ "$JSON_READER" = "node" ]; then
  # Uma chamada de node para o diretório inteiro. Um processo por arquivo custa
  # caro e não acrescenta nada.
  node -e '
    const fs = require("fs"), path = require("path");
    const dir = process.argv[1];
    let names = [];
    try { names = fs.readdirSync(dir); } catch (e) { process.exit(0); }
    for (const name of names.filter(n => /^check-.*\.json$/.test(n))) {
      let j;
      try { j = JSON.parse(fs.readFileSync(path.join(dir, name), "utf8")); }
      catch (e) { continue; }
      if (!j.agent) continue;
      const f = Array.isArray(j.findings) ? j.findings : [];
      const crit = f.filter(x => x && x.severity === "crit").length;
      const high = f.filter(x => x && x.severity === "high").length;
      const mt = (j.missing_tool === null || j.missing_tool === undefined) ? "0" : "1";
      // v0.79: evidencia estatica x dinamica. Um check dinamico que nao
      // exercitou nada nao pode alimentar um gate como se tivesse medido.
      const dyn = j.evidence_kind === "dynamic" ? "1" : "0";
      const exercised = j.exercised === true ? "1" : "0";
      process.stdout.write([j.agent, j.status || "unknown", crit, high, mt, dyn, exercised].join("|") + "\n");
    }
  ' "$RESULTS_DIR" > "$RAW" 2>/dev/null || true
else
  for f in "$RESULTS_DIR"/check-*.json; do
    [ -f "$f" ] || continue
    agent=$(jq -r '.agent // ""' "$f" 2>/dev/null)
    [ -z "$agent" ] && continue
    status=$(jq -r '.status // "unknown"' "$f" 2>/dev/null)
    crit=$(jq '[.findings[]? | select(.severity=="crit")] | length' "$f" 2>/dev/null || echo 0)
    high=$(jq '[.findings[]? | select(.severity=="high")] | length' "$f" 2>/dev/null || echo 0)
    # missing_tool != null significa "não verificado", que é buraco de cobertura.
    # Ler isso como aprovação é o modo de falha que este arquivo existe pra evitar.
    mt=$(jq -r 'if .missing_tool == null then "0" else "1" end' "$f" 2>/dev/null || echo 0)
    dyn=$(jq -r 'if .evidence_kind == "dynamic" then "1" else "0" end' "$f" 2>/dev/null || echo 0)
    exercised=$(jq -r 'if .exercised == true then "1" else "0" end' "$f" 2>/dev/null || echo 0)
    printf '%s|%s|%s|%s|%s|%s|%s\n' "$agent" "$status" "$crit" "$high" "$mt" "$dyn" "$exercised" >> "$RAW"
  done
fi

ROWS=$(mktemp)
while IFS='|' read -r agent status crit high mt dyn exercised; do
  [ -z "${agent:-}" ] && continue
  printf '%s|%s|%s|%s|%s|%s|%s|%s\n' "$(gate_of "$agent")" "$agent" "$status" "$crit" "$high" "$mt" "${dyn:-0}" "${exercised:-0}" >> "$ROWS"
done < "$RAW"
rm -f "$RAW"

# ─── Regras extras: evidência positiva, não só ausência de finding ───
# Backup existir não é a mesma coisa que restore funcionar. Deploy existir não é
# a mesma coisa que ter caminho de volta.
has_restore_evidence() {
  # O check-backup-restore-tested mede isto com mais cuidado do que um `ls`:
  # ele exige script, teste, job de CI ou runbook com verificacao, e distingue
  # "ha caminho de restore" de "ninguem nunca rodou". Quando ele passou, a
  # evidencia existe; quando falhou, nao existe — e o `ls` nao tem por que
  # discordar. Sem o result dele, cai na heuristica antiga.
  local r="$RESULTS_DIR/check-backup-restore-tested.json"
  if [ -f "$r" ]; then
    grep -q '"status"[[:space:]]*:[[:space:]]*"passed"' "$r" 2>/dev/null && return 0
    grep -q '"status"[[:space:]]*:[[:space:]]*"failed"' "$r" 2>/dev/null && return 1
  fi
  ls docs/*restore* docs/**/*restore* scripts/*restore* 2>/dev/null | head -1 | grep -q . && return 0
  grep -rqil 'restore' docs/runbooks 2>/dev/null && return 0
  return 1
}
has_rollback_evidence() {
  local r="$RESULTS_DIR/check-rollback-ready.json"
  if [ -f "$r" ]; then
    grep -q '"status"[[:space:]]*:[[:space:]]*"passed"' "$r" 2>/dev/null && return 0
    grep -q '"status"[[:space:]]*:[[:space:]]*"failed"' "$r" 2>/dev/null && return 1
  fi
  ls docs/*rollback* scripts/*rollback* 2>/dev/null | head -1 | grep -q . && return 0
  grep -rqil 'rollback' docs 2>/dev/null && return 0
  return 1
}

echo "═══ blindar release gates ═══"
echo ""
printf "%-18s %-22s %s\n" "GATE" "STATUS" "EVIDÊNCIA"
printf "%s\n" "──────────────────────────────────────────────────────────────────────"

BLOCKED_N=0; WARN_N=0
JSON_GATES=""

for g in $GATES; do
  n=$(awk -F'|' -v g="$g" '$1==g' "$ROWS" | wc -l | tr -d ' ')
  if [ "$n" -eq 0 ]; then
    # Dimensão sem check executado NÃO é aprovação. "Não rodou" e "não se
    # aplica" são estados diferentes, e só o operador sabe distinguir: um CLI
    # legitimamente não tem gate de QUALITY de frontend, mas um SaaS sem nenhum
    # check de DATABASE tem um buraco, não uma isenção. Conta como warning e é
    # dispensável por aceite assinado, como qualquer outro.
    status="NOT VERIFIED"; evid="nenhum check desta dimensão executou — aceite em .accept-risk.md se não se aplica"
  else
    ncrit=$(awk -F'|' -v g="$g" '$1==g {s+=$4} END{print s+0}' "$ROWS")
    nhigh=$(awk -F'|' -v g="$g" '$1==g {s+=$5} END{print s+0}' "$ROWS")
    nfail=$(awk -F'|' -v g="$g" '$1==g && $3=="failed"' "$ROWS" | wc -l | tr -d ' ')
    nunver=$(awk -F'|' -v g="$g" '$1==g && $6=="1"' "$ROWS" | wc -l | tr -d ' ')

    if [ "$ncrit" -gt 0 ]; then
      status="BLOCKED"; evid="$ncrit crit em $n check(s)"
    elif [ "$nunver" -gt 0 ]; then
      status="PASS WITH WARNINGS"; evid="$nunver check(s) não verificados (ferramenta ausente)"
    elif [ "$nfail" -gt 0 ]; then
      status="PASS WITH WARNINGS"; evid="$nfail check(s) com finding, $nhigh high"
    else
      status="PASS"; evid="$n check(s), 0 finding"
    fi
  fi

  # ─── NOT EXERCISED: estrutura verificada, comportamento não ───
  # Só se aplica quando o gate CHEGARIA a PASS. Gate já em BLOCKED ou com
  # warning não melhora nem piora por causa disto — o que este estado existe
  # para impedir é o verde limpo em cima de nenhuma medição dinâmica.
  ndyn=$(awk -F'|' -v g="$g" '$1==g && $7=="1" && $8=="1"' "$ROWS" | wc -l | tr -d ' ')
  ndyn_tentou=$(awk -F'|' -v g="$g" '$1==g && $7=="1"' "$ROWS" | wc -l | tr -d ' ')
  case " $DYNAMIC_REQUIRED " in
    *" $g "*)
      if [ "$status" = "PASS" ] && [ "${ndyn:-0}" -eq 0 ]; then
        status="NOT EXERCISED"
        if [ "${ndyn_tentou:-0}" -gt 0 ]; then
          evid="$n check(s) estático(s) sem finding, e ${ndyn_tentou} check(s) dinâmico(s) rodaram sem exercitar o sistema (sem alvo/docker/autorização) — estrutura verificada, comportamento não"
        else
          evid="$n check(s) estático(s) sem finding, e nenhum check dinâmico rodou — ninguém tocou o sistema no ar nesta dimensão"
        fi
      elif [ "$status" = "PASS" ]; then
        evid="$evid, ${ndyn} exercitado(s) contra o sistema no ar"
      fi
      ;;
  esac

  # Overrides: gates que exigem prova positiva
  if [ "$g" = "BACKUP_RECOVERY" ] && [ "$status" = "PASS" ] && ! has_restore_evidence; then
    status="PASS WITH WARNINGS"
    evid="backup ok, mas sem evidência de RESTORE testado — backup nunca restaurado é hipótese"
  fi
  if [ "$g" = "DEPLOYMENT" ] && [ "$status" = "PASS" ] && ! has_rollback_evidence; then
    status="PASS WITH WARNINGS"
    evid="sem caminho de rollback documentado"
  fi
  # O host é metade do DEPLOYMENT e o blindar não enxerga essa metade: firewall
  # ativo, certificado válido, backup fresco, DNS e vizinho de container só se
  # veem no servidor. Quem verifica é a skill irmã `ancorar`, e o blindar só LÊ
  # o que ela produziu — nunca escreve em .ancorar/.
  # Host não verificado NÃO é host aprovado, pela mesma regra do NOT VERIFIED.
  if [ "$g" = "DEPLOYMENT" ] && [ "$status" = "PASS" ]; then
    if [ -d ".ancorar/results" ]; then
      ANC_FAIL=$(grep -l '"status"[[:space:]]*:[[:space:]]*"failed"' .ancorar/results/*.json 2>/dev/null | wc -l | tr -d ' ')
      if [ "${ANC_FAIL:-0}" -gt 0 ]; then
        status="BLOCKED"
        evid="ancorar reprovou $ANC_FAIL check(s) no host — o código passa, o servidor não"
      fi
    else
      status="PASS WITH WARNINGS"
      evid="código pronto, mas o HOST nunca foi verificado (sem .ancorar/results) — rode: bash scripts/ancorar-bridge.sh --host <host>"
    fi
  fi

  case "$status" in
    BLOCKED) BLOCKED_N=$((BLOCKED_N+1)) ;;
    "PASS WITH WARNINGS"|"NOT VERIFIED"|"NOT EXERCISED") WARN_N=$((WARN_N+1)) ;;
  esac

  printf "%-18s %-22s %s\n" "$g" "$status" "$evid"
  JSON_GATES="${JSON_GATES}{\"gate\":\"$g\",\"status\":\"$status\",\"checks\":$n,\"evidence\":\"$evid\"},"
done

# ─── Fora do veredito: por desenho × buraco ───
# Dois blocos separados de propósito. Enquanto eram um só, a lista de "sem gate"
# misturava o scanner de stack, que nunca acha nada, com o check de PCI, que
# acha crítico — e uma lista onde o ruído esperado mora junto do buraco não é
# lida por ninguém.
OOG=$(awk -F'|' '$1=="OUT_OF_GATE" {print $2}' "$ROWS" | sort -u)
if [ -n "$OOG" ]; then
  echo ""
  echo "ℹ  fora do veredito por desenho (o achado sai no relatório, não no gate):"
  while IFS= read -r a; do
    [ -z "$a" ] && continue
    printf "     %-30s %s\n" "$a" "$(motivo_fora_do_gate "$a")"
  done <<< "$OOG"
fi

# Checks sem gate: buraco de mapeamento, e buraco pesa no veredito.
# Até a v0.80 isto era só uma linha de aviso, e a linha dizia em voz alta que os
# achados não contavam — sem que nada acontecesse por causa disso. Um crit que
# ninguém conta é um crit que passa: o mesmo defeito do "critical" fora do enum,
# que existia no JSON e não era contado por nenhum consumidor.
UNMAPPED_N=$(awk -F'|' '$1=="UNMAPPED"' "$ROWS" | wc -l | tr -d ' ')
UNMAPPED_CRIT=$(awk -F'|' '$1=="UNMAPPED" {s+=$4} END{print s+0}' "$ROWS")
if [ "${UNMAPPED_N:-0}" -gt 0 ]; then
  echo ""
  echo "⚠  $UNMAPPED_N check(s) sem gate mapeado — rodaram e não chegam a dimensão nenhuma:"
  awk -F'|' '$1=="UNMAPPED" {printf "     %-30s %-8s %s crit, %s high\n", $2, $3, $4, $5}' "$ROWS" | sort
  echo "   Mapeie em gate_of(), ou declare o motivo em motivo_fora_do_gate()."
  if [ "${UNMAPPED_CRIT:-0}" -gt 0 ]; then
    echo "   → $UNMAPPED_CRIT crit em check não mapeado. Crítico que ninguém conta é crítico que passa: BLOQUEIA."
    BLOCKED_N=$((BLOCKED_N+1))
  else
    echo "   → cobertura invisível conta como warning: não é PASS nem é reprovação, é 'ninguém decidiu'."
    WARN_N=$((WARN_N+1))
  fi
fi

TOTAL_CHECKS=$(wc -l < "$ROWS" | tr -d ' ')

if [ "$TOTAL_CHECKS" -eq 0 ]; then
  # Nenhum check produziu resultado. Sem medição não há veredito, e a ausência
  # de medição nunca pode virar aprovação.
  VERDICT="NO-GO"; EXIT_CODE=2
  echo ""
  echo "❌ nenhum check produziu resultado em $RESULTS_DIR — nada foi medido."
elif [ "$BLOCKED_N" -gt 0 ]; then
  VERDICT="NO-GO"; EXIT_CODE=2
elif [ "$WARN_N" -gt 0 ]; then
  VERDICT="CONDITIONAL GO"; EXIT_CODE=1
else
  VERDICT="GO"; EXIT_CODE=0
fi

# As duas listas entram no gates.json: o relatório da Fase 07 precisa dizer o que
# ficou fora e por quê, e "não citou" não pode ser indistinguível de "não havia".
JSON_OOG=$(awk -F'|' '$1=="OUT_OF_GATE" {print $2}' "$ROWS" | sort -u | awk '{printf "\"%s\",", $1}')
JSON_OOG="${JSON_OOG%,}"
JSON_UNMAPPED=$(awk -F'|' '$1=="UNMAPPED" {print $2}' "$ROWS" | sort -u | awk '{printf "\"%s\",", $1}')
JSON_UNMAPPED="${JSON_UNMAPPED%,}"

mkdir -p "$BLINDAR_DIR"
cat > "$GATES_OUT" <<EOF
{
  "schema": "blindar/gates@v1",
  "generated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "verdict": "$VERDICT",
  "blocked_gates": $BLOCKED_N,
  "warning_gates": $WARN_N,
  "gates": [${JSON_GATES%,}],
  "out_of_gate": [${JSON_OOG}],
  "unmapped": [${JSON_UNMAPPED}]
}
EOF

echo ""
echo "══════════════════════════════════════════════════════════════════════"
echo "  VEREDITO: $VERDICT   (BLOCKED=$BLOCKED_N  WARNINGS=$WARN_N)"
echo "══════════════════════════════════════════════════════════════════════"
[ "$VERDICT" = "CONDITIONAL GO" ] && echo "  Cada WARNING precisa de aceite assinado em .accept-risk.md."
[ "$VERDICT" = "NO-GO" ] && echo "  Gate BLOCKED bloqueia release independente da contagem de crit/high."
echo "  Detalhe: $GATES_OUT"

rm -f "$ROWS"
exit $EXIT_CODE
