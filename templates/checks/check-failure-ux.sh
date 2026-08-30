#!/usr/bin/env bash
# check-failure-ux — o que o CLIENTE recebe quando quebra.
#
# Os checks de resiliência do blindar medem a estrutura: existe breaker, existe
# retry, existe try/catch. Nenhum deles olha a resposta que chega na tela.
#
# São coisas diferentes, e a segunda é a que o usuário vive:
#   • 500 onde o certo era 404 — erro de rota vira erro de servidor no painel
#   • stack trace no corpo — caminho de arquivo, versão de framework, query SQL
#   • 401 por falha de infraestrutura — o banco tossiu e o usuário foi deslogado
#   • HTML de erro num endpoint JSON — o front quebra parseando a página de erro
#   • corpo vazio com 5xx — o cliente não tem o que mostrar além de "algo deu errado"
#
# Este check provoca cada situação contra o alvo vivo e lê a resposta.
#
# Uso: bash check-failure-ux.sh --url http://localhost:3000 [--health /healthz]

BLINDAR_AGENT="check-failure-ux"
STARTED_AT=$(date -u +%s)
source "$(dirname "$0")/_lib.sh"
source "$(dirname "$0")/_dyn.sh"
declare_dynamic

log_section "UX de falha (o que o cliente recebe quando quebra)"

dyn_parse_args "$@"

dyn_need_curl   || { emit_result "$BLINDAR_AGENT" "skipped" 0; exit 0; }
dyn_need_target || { emit_result "$BLINDAR_AGENT" "skipped" 0; exit 0; }

BASE="${DYN_TARGET%/}"

# Pré-condição: o alvo precisa estar de pé, senão TODA resposta é falha de rede
# e o check mediria o próprio ambiente em vez da app.
PRE=$(dyn_probe "${BASE}${DYN_HEALTH}" 10)
PRE_CODE=$(echo "$PRE" | awk '{print $1}')
case "$PRE_CODE" in
  2*|3*) : ;;
  *)
    not_exercised "alvo respondeu $PRE_CODE no health — sem app de pe nao da para medir a UX de falha dela"
    log_warn "Health devolveu $PRE_CODE — abortando."
    emit_result "$BLINDAR_AGENT" "skipped" 0
    exit 0
    ;;
esac
mark_exercised

FAIL=0
PROBES=""

# Padrões de vazamento: rastro de execução que nunca deveria sair do servidor.
LEAK_RE='Traceback \(most recent|at [A-Za-z_$][A-Za-z0-9_$]*\.[A-Za-z0-9_$]+ \(|\.js:[0-9]+:[0-9]+|node_modules[/\\]|site-packages[/\\]|SQLSTATE|SequelizeDatabaseError|PrismaClientKnownRequest|org\.springframework|System\.NullReference|panic: runtime error'

registra() { # nome codigo esperado corpo content_type
  PROBES="${PROBES}{\"probe\":\"$1\",\"code\":\"$2\",\"content_type\":\"$5\"},"
}

# ─── Probe 1: rota inexistente ───
# 404 é a resposta correta. 500 significa que o handler de rota desconhecida
# está estourando exceção em vez de responder.
P="$BASE/blindar-rota-que-nao-existe-$$"
R=$(dyn_probe_body "$P" 10); C=$(dyn_code_of "$R"); B=$(dyn_body_of "$R")
CT=$(curl -s -o /dev/null -w '%{content_type}' --max-time 10 "$P" 2>/dev/null)
registra "rota-inexistente" "$C" "404" "$B" "$CT"
log_info "rota inexistente → $C"
case "$C" in
  5*) add_finding "high" "Rota inexistente devolveu $C em vez de 404: o handler de rota desconhecida estoura exceção. Todo bot varrendo URL gera erro de servidor, e o alerta de 5xx vira ruído até ninguém mais olhar" "" ""; FAIL=1 ;;
  000) add_finding "high" "Rota inexistente derrubou a conexão (sem resposta) em vez de devolver 404" "" ""; FAIL=1 ;;
esac
if printf '%s' "$B" | grep -qE "$LEAK_RE"; then
  add_finding "crit" "A resposta de rota inexistente vaza rastro de execução (stack trace / caminho de arquivo / erro de driver) para o cliente. Isso entrega ao atacante o framework, a versão e a estrutura de diretórios de graça" "$P" ""
  FAIL=1
fi

# ─── Probe 2: JSON malformado num endpoint de API ───
# Espera-se 400. 500 significa que o parser de corpo não é tratado.
API="$BASE/api"
R=$(dyn_probe_body "$API" 10 -X POST -H "Content-Type: application/json" --data-binary '{"a":')
C=$(dyn_code_of "$R"); B=$(dyn_body_of "$R")
registra "json-malformado" "$C" "400" "$B" ""
log_info "JSON malformado em /api → $C"
case "$C" in
  5*) add_finding "high" "Corpo JSON malformado devolveu $C em vez de 400: o erro de parsing não é tratado e sobe como falha de servidor. Cliente que erra o payload não consegue distinguir o próprio bug de um incidente" "" ""; FAIL=1 ;;
esac
if printf '%s' "$B" | grep -qE "$LEAK_RE"; then
  add_finding "crit" "A resposta a JSON malformado vaza rastro de execução para o cliente" "$API" ""
  FAIL=1
fi

# ─── Probe 3: Content-Type coerente no caminho de erro ───
# Endpoint de API que responde HTML no erro quebra o front no JSON.parse, e a
# mensagem que aparece é "Unexpected token <" — que não diz nada a ninguém.
CT_API=$(curl -s -o /dev/null -w '%{content_type}' --max-time 10 \
  -X POST -H "Content-Type: application/json" --data-binary '{"a":' "$API" 2>/dev/null)
case "$CT_API" in
  *text/html*)
    add_finding "med" "O endpoint /api responde text/html no caminho de erro. O cliente que faz JSON.parse recebe 'Unexpected token <' em vez da mensagem do erro — a causa real fica invisível dos dois lados" "$API" ""
    ;;
esac

# ─── Probe 4: falha de infraestrutura não pode deslogar ───
# Só roda com docker: congela a dependência e olha o que o cliente recebe.
# 401/403 aqui é o pior desfecho possível — o banco tossiu e o produto disse ao
# usuário que ele não tem permissão. Ele vai tentar logar de novo, e falhar.
INFRA_CODE="nao-testado"
if ensure_docker_up; then
  TARGET_PORT=$(dyn_port_of_target "$BASE")
  dyn_pick_dependency "postgres|mysql|mariadb|mongo|redis|valkey" "$TARGET_PORT" || true
  DEP="$DYN_DEP"
  if [ -n "$DEP" ] && dyn_freeze "$DEP"; then
    log_info "Congelei $DEP — lendo a resposta que o cliente recebe..."
    R=$(dyn_probe_body "${BASE}${DYN_HEALTH}" 15)
    INFRA_CODE=$(dyn_code_of "$R"); B=$(dyn_body_of "$R")
    dyn_unfreeze "$DEP"; trap - EXIT INT TERM
    log_info "sob falha de dependência → $INFRA_CODE"
    registra "dependencia-congelada" "$INFRA_CODE" "503" "$B" ""
    case "$INFRA_CODE" in
      401|403)
        add_finding "crit" "Com a dependência congelada, o cliente recebeu $INFRA_CODE (não autorizado). Falha de infraestrutura está sendo traduzida como problema de credencial: o usuário é deslogado por causa do banco, tenta logar de novo e falha de novo" "" ""
        FAIL=1 ;;
      503|502|504) log_pass "Falha de dependência vira $INFRA_CODE — status honesto" ;;
      500)
        add_finding "high" "Com a dependência congelada, o cliente recebeu 500 genérico em vez de 503. 500 diz 'bug nosso' e 503 diz 'indisponível, tente de novo' — cliente e monitoramento tratam os dois de formas diferentes" "" ""
        FAIL=1 ;;
      000)
        add_finding "high" "Com a dependência congelada, a requisição não recebeu resposta nenhuma. O cliente fica pendurado sem status: não há o que mostrar na tela nem o que registrar no log" "" ""
        FAIL=1 ;;
    esac
    if printf '%s' "$B" | grep -qE "$LEAK_RE"; then
      add_finding "crit" "Sob falha de dependência a resposta vaza rastro de execução (driver, query ou caminho de arquivo) para o cliente" "" ""
      FAIL=1
    fi
  else
    log_warn "Sem container de dependência para congelar — probe de falha de infra não rodou."
    add_finding "low" "Probe de falha de infraestrutura não executado (sem container de dependência): a tradução erro-de-infra → status-do-cliente segue não verificada" "" ""
  fi
else
  log_warn "Docker indisponível — probe de falha de infra não rodou."
  add_finding "low" "Probe de falha de infraestrutura não executado (sem docker): a tradução erro-de-infra → status-do-cliente segue não verificada" "" ""
fi

mkdir -p "$BLINDAR_DIR" 2>/dev/null || true
cat > "$BLINDAR_DIR/failure-ux.json" <<EOF
{
  "schema": "blindar/failure-ux@v1",
  "ran_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "target": "$BASE",
  "probes": [${PROBES%,}],
  "under_dependency_failure": "$INFRA_CODE"
}
EOF

if [ "$FAIL" -eq 1 ]; then
  emit_result "$BLINDAR_AGENT" "failed" 1
  exit 1
fi
emit_result "$BLINDAR_AGENT" "passed" 0
exit 0
