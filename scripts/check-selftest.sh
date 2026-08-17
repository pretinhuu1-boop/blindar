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
  # check-secrets NAO tinha par: o unico fixture de segredo e mascarado de
  # proposito, entao o gitleaks nunca disparava nele. Sem disparo nao ha
  # contrato, e o falso negativo do scan do indice vazio viveu ali.
  "check-secrets.sh              | project-gitleaks-bad    | project-gitleaks-good"
  "check-gitleaks.sh             | project-gitleaks-bad    | project-gitleaks-good"
  "check-horizontal-scale.sh     | project-hscale-bad      | project-hscale-good"
  "check-semgrep.sh              | project-sast-bad        | project-sast-good"
  "check-wave-guardian.sh        | project-wave-bad        | project-wave-good"
  "check-functional-e2e.sh       | project-e2e-bad         | project-e2e-good"
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
  "check-invisible-unicode.sh    | project-unicode-bad     | project-unicode-good"
  "check-seo-foundation.sh       | project-seofound-bad    | project-seofound-good"
  # blindar-learn:insert (mantenha — scripts/blindar-learn.sh insere novos pares acima desta linha)
)

# Retorna o STATUS canônico do check (passed|failed|skipped), lendo o result JSON.
# blindar agrega por status, não por exit code (checks só-med emitem failed+exit0).
run_status() { # dir check → echo status
  local dir="$1" ck="$2"
  # ─── Fixture cujo insumo É o .blindar ───
  # Alguns checks leem a saída do próprio blindar (wave-guardian lê o
  # run-report.json, e decide fechar ou não a onda a partir dele). O fixture
  # desses precisa TRAZER um .blindar — e o `rm -rf` abaixo, que existe para não
  # deixar result velho contaminar a rodada, apagava justamente o insumo.
  #
  # Sintoma: o fixture limpo do wave-guardian dava falso-positivo, porque o
  # check encontrava o run-report ausente. O fixture estava certo; o gate é que
  # destruía a pré-condição antes de medir.
  local guardado=""
  if [ -d "$dir/.blindar" ]; then
    guardado=$(mktemp -d)
    cp -r "$dir/.blindar/." "$guardado/" 2>/dev/null || true
  fi
  rm -rf "$dir/.blindar"
  if [ -n "$guardado" ]; then
    mkdir -p "$dir/.blindar"
    cp -r "$guardado/." "$dir/.blindar/" 2>/dev/null || true
  fi
  ( cd "$dir" && bash "$CHECKS_DIR/$ck" >/dev/null 2>&1 ); local rc=$?
  local rf="$dir/.blindar/results/${ck%.sh}.json" st=""
  LAST_MISSING_TOOL=""
  if [ -f "$rf" ]; then
    st=$(grep -oE '"status"[[:space:]]*:[[:space:]]*"[a-z]+"' "$rf" | head -1 | sed -E 's/.*"([a-z]+)".*/\1/')
    # Precisa sair daqui: as linhas seguintes apagam o .blindar.
    LAST_MISSING_TOOL=$(grep -oE '"missing_tool"[[:space:]]*:[[:space:]]*"[^"]+"' "$rf" \
      | head -1 | sed -E 's/.*:[[:space:]]*"([^"]+)".*/\1/')
  fi
  [ -z "$st" ] && { if [ "$rc" -ne 0 ]; then st="failed"; else st="passed"; fi; }

  # O `$dir` é o diretório REAL do fixture, versionado. Apagar o .blindar aqui
  # sem devolver o que veio com ele destruiria o insumo do fixture no repositório
  # — a primeira execução funcionaria e a segunda não, e o `git status` acusaria
  # arquivo apagado que ninguém apagou de propósito.
  rm -rf "$dir/.blindar"
  if [ -n "$guardado" ]; then
    mkdir -p "$dir/.blindar"
    cp -r "$guardado/." "$dir/.blindar/" 2>/dev/null || true
    rm -rf "$guardado"
  fi
  echo "$st"
}

echo "${B}═══ blindar check self-test ═══${RST}"
PASS=0; FAIL=0; FAILED=()
declare -A VERIFIED=()
NAOVER=()   # par registrado que a MAQUINA nao consegue avaliar

for row in "${PAIRS[@]}"; do
  IFS='|' read -r ck vuln clean <<< "$row"
  ck=$(echo "$ck" | xargs); vuln=$(echo "$vuln" | xargs); clean=$(echo "$clean" | xargs)
  [ ! -f "$CHECKS_DIR/$ck" ] && { echo "${Y}SKIP${RST} $ck (check ausente)"; continue; }

  local_ok=1
  # 1) dispara no vulnerável → status DEVE ser failed
  if [ -d "$FIXTURES_DIR/$vuln" ]; then
    st=$(run_status "$FIXTURES_DIR/$vuln" "$ck")
    # `skipped` no fixture VULNERÁVEL não é o check errando: é a máquina sem a
    # ferramenta que o check invoca. Contar como regressão faria o gate reprovar
    # por causa do ambiente; contar como ✓ seria pior ainda, porque diria
    # "verificado" sobre algo que ninguém executou. É um terceiro estado.
    if [ "$st" = "skipped" ]; then
      mt="$LAST_MISSING_TOOL"
      echo "${Y}⊘${RST} $ck  — NÃO VERIFICADO nesta máquina (falta ${mt:-ferramenta externa})"
      NAOVER+=("$ck (${mt:-ferramenta externa})")
      continue
    fi
    if [ "$st" != "failed" ]; then local_ok=0; reason="não disparou no vulnerável ($vuln, status=$st)"; fi
  else
    # Fixture some e o par vira SKIP silencioso: a cobertura cai e o gate segue
    # verde. Aconteceu nesta sessao — apaguei project-deps-* achando que era meu
    # e era do check-deps-sync. Par registrado sem fixture e regressao.
    echo "${R}✗${RST} $ck  — fixture $vuln AUSENTE (par registrado sem fixture)"
    FAIL=$((FAIL+1)); FAILED+=("$ck: fixture $vuln ausente"); continue
  fi
  # 2) cala no limpo → status NÃO pode ser failed (passed/skipped ok)
  if [ -d "$FIXTURES_DIR/$clean" ]; then
    st=$(run_status "$FIXTURES_DIR/$clean" "$ck")
    if [ "$st" = "failed" ]; then local_ok=0; reason="falso-positivo no limpo ($clean, status=$st)"; fi
  else
    echo "${R}✗${RST} $ck  — fixture $clean AUSENTE (par registrado sem fixture)"
    FAIL=$((FAIL+1)); FAILED+=("$ck: fixture $clean ausente"); continue
  fi

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

  # ─── Par registrado É a resposta ───
  # As heurísticas abaixo servem para decidir sobre check SEM par: elas tentam
  # adivinhar se daria para contratar. Quando o par existe e passa, não há o que
  # adivinhar — alguém já provou que o check dispara no vulnerável e cala no
  # limpo.
  #
  # Sem esta regra o check entrava no numerador (tem par verificado) e ficava
  # fora do denominador (a heurística o recusava), e a cobertura saía 78/77 =
  # 101%. Aconteceu duas vezes: com os wrappers de scanner e depois com o
  # check-functional-e2e, que a regra do `npx` recusava. Métrica que passa de
  # 100% não está medindo o que diz medir.
  local _p
  for _p in "${PAIRS[@]}"; do
    case "${_p%%|*}" in *"$base"*) return 0 ;; esac
  done

  grep -qE 'emit_result[^\n]*"failed"' "$f" || return 1   # 2
  grep -qE '\$HOME|\$\{HOME|\$APPDATA|\$\{APPDATA' "$f" && return 1  # 3
  grep -qE 'npx |curl |wget ' "$f" && return 1            # 4
  echo "$base" | grep -qE "$SCANNER_WRAPPERS" && return 1 # 5
  return 0
}

# ─── Por que cada check fora do gate está fora ───
# "32 excluídos" não é informação: é um número onde deveria haver um motivo.
# Enquanto for um balde só, ninguém sabe se lá dentro tem check que PODERIA ter
# contrato e só não tem — foi exatamente o caso do check-secrets, que passou
# meses no balde carregando um falso negativo.
#
# Cada exclusão agora tem nome, e cada nome diz qual OUTRA coisa cobre aquele
# check. Excluído sem cobertura alternativa é dívida declarada, não silêncio.
motivo_exclusao() { # basename → motivo, ou vazio se é gate-ável
  case "$1" in
    *.api.sh)
      echo "julgamento é do LLM — o CÓDIGO tem contrato em tests/api-contract.test.mjs" ;;
    check-release-gates.sh|check-termination.sh)
      echo "é o GATE, não um check: decide por exit code sobre os results dos outros" ;;
    check-evidence.sh|check-mcp-recommended.sh|check-strategic-scanner.sh|check-content-quality.sh)
      echo "informativo por desenho: nunca emite 'failed', então não há o que contratar" ;;
    check-lighthouse.sh|check-visual-regression.sh|check-bundle-size.sh)
      echo "só chega a veredito rodando serviço externo (Chrome, Chromatic, build real)" ;;
    check-ai-powered-example.sh)
      echo "template de exemplo para escrever check novo, não roda em auditoria" ;;
    check-trivy.sh|check-osv-scanner.sh|check-deps-audit.sh)
      echo "o veredito e do scanner: exige rede e base de CVE atualizada, e par de fixture aqui deixaria o gate lento e instavel" ;;
    check-mcp-security.sh)
      echo "lê config MCP em \$HOME — o veredito depende da máquina, não do projeto" ;;
    *) echo "" ;;
  esac
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

# ─── A meta escrita passa a ser cobrada ───
# A linha "Cada check novo DEVE entrar em PAIRS antes de mergear" já estava
# impressa aqui, e não era verificada por ninguém. Escrever a regra e não cobrar
# é a mesma coisa que não ter regra — só que com a aparência de ter.
#
# Foi medido: um check novo entrou na árvore no meio de uma rodada, a cobertura
# caiu para 78/79 e o resumo continuou dizendo "todos os pares registrados
# corretos". Estava certo sobre os pares registrados, e calado sobre o que não
# foi registrado — que é justamente o buraco.
SEM_PAR=()
for _g in "${GATEABLE_LIST[@]}"; do
  [ -n "${VERIFIED[$_g]:-}" ] || SEM_PAR+=("$_g")
done
if [ "${#SEM_PAR[@]}" -gt 0 ]; then
  echo ""
  echo "${R}${B}✗ ${#SEM_PAR[@]} check(s) gate-ável(is) sem par de fixture:${RST}"
  for _c in "${SEM_PAR[@]}"; do echo "    $_c"; done
  echo "  Gate-ável quer dizer que DÁ para contratar. Sem par, o check roda em"
  echo "  produção sem ninguém nunca ter provado que ele dispara."
  FAIL=$((FAIL + ${#SEM_PAR[@]}))
  FAILED+=("${#SEM_PAR[@]} check(s) gate-ável(is) sem par de fixture")
fi

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

# Cada check fora do gate, com o motivo e o que cobre ele no lugar.
SEM_MOTIVO=()
declare -A _POR_MOTIVO=()
while IFS= read -r _f; do
  _b=$(basename "$_f")
  case " ${GATEABLE_LIST[*]} " in *" $_b "*) continue ;; esac
  _m=$(motivo_exclusao "$_b")
  if [ -z "$_m" ]; then SEM_MOTIVO+=("$_b")
  else _POR_MOTIVO["$_m"]="${_POR_MOTIVO["$_m"]:-}${_b} "; fi
done < <(find "$CHECKS_DIR" -maxdepth 1 -name 'check-*.sh' 2>/dev/null | sort)

if [ "${#_POR_MOTIVO[@]}" -gt 0 ]; then
  echo ""
  echo "${B}── fora do gate, e por quê ──${RST}"
  for _m in "${!_POR_MOTIVO[@]}"; do
    _n=$(printf '%s' "${_POR_MOTIVO[$_m]}" | wc -w | tr -d ' ')
    echo "  ${_n}×  $_m"
    for _c in ${_POR_MOTIVO[$_m]}; do echo "        $_c"; done
  done
fi
if [ "${#SEM_MOTIVO[@]}" -gt 0 ]; then
  echo ""
  echo "${R}${B}✗ ${#SEM_MOTIVO[@]} check(s) fora do gate SEM motivo declarado:${RST}"
  for _c in "${SEM_MOTIVO[@]}"; do echo "    $_c"; done
  echo "  Ou entra em PAIRS, ou ganha um motivo em motivo_exclusao(). Balde sem"
  echo "  nome foi onde o falso negativo do check-secrets morou por meses."
  FAIL=$((FAIL + ${#SEM_MOTIVO[@]}))
  FAILED+=("${#SEM_MOTIVO[@]} check(s) fora do gate sem motivo declarado")
fi
if [ "${#NAOVER[@]}" -gt 0 ]; then
  echo ""
  echo "${Y}NÃO VERIFICADOS nesta máquina (${#NAOVER[@]}) — o par existe, a ferramenta não:${RST}"
  for n in "${NAOVER[@]}"; do echo "  ⊘ $n"; done
  echo "  Não entram como aprovados nem como regressão. Instale e rode de novo."
fi

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
