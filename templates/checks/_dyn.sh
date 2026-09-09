#!/usr/bin/env bash
# blindar — harness DINÂMICO compartilhado (v0.79.0)
#
# Source DEPOIS do _lib.sh, nos checks que exercitam o sistema no ar:
#   source "$(dirname "$0")/_lib.sh"
#   source "$(dirname "$0")/_dyn.sh"
#   declare_dynamic
#
# Por que existe: até a v0.78 os 101 checks determinísticos liam o repositório.
# Eles provam que a ESTRUTURA existe — há código de breaker, há try/catch, há
# header configurado. Nenhum deles derruba uma dependência e mede o que
# acontece, nem manda uma requisição de fora e compara com a de dentro.
#
# Este arquivo é a caixa de ferramentas para isso: resolver o alvo, medir
# percentis de latência, injetar falha em container, rodar de outra origem de
# rede. Cada primitiva devolve dados; a decisão de reprovar fica com o check.

# ─── Resolução de alvo ───
# Precedência: --url do check > BLINDAR_TARGET_URL > .blindar/target.url
# Sem alvo NÃO é erro: é ausência de pré-condição, e quem chama traduz em
# not_exercised — nunca em passed.
DYN_URL="${DYN_URL:-}"
DYN_TARGET="${DYN_TARGET:-}"
DYN_HEALTH="${DYN_HEALTH:-/healthz}"
DYN_SERVICE="${DYN_SERVICE:-}"

dyn_resolve_target() {
  [ -n "$DYN_URL" ] && { echo "$DYN_URL"; return 0; }
  [ -n "${BLINDAR_TARGET_URL:-}" ] && { echo "$BLINDAR_TARGET_URL"; return 0; }
  if [ -f "$BLINDAR_DIR/target.url" ]; then
    local u; u=$(head -1 "$BLINDAR_DIR/target.url" | tr -d '\r' | xargs)
    [ -n "$u" ] && { echo "$u"; return 0; }
  fi
  return 1
}

# Parse de argumentos comum a todo check dinâmico. Chame com "$@".
dyn_parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --url)     DYN_URL="${2:-}"; shift 2 ;;
      --health)  DYN_HEALTH="${2:-}"; shift 2 ;;
      --service) DYN_SERVICE="${2:-}"; shift 2 ;;
      *) shift ;;
    esac
  done
}

# ─── Pré-condições ───
# Todas devolvem 1 e JÁ registram o motivo em not_exercised. O check faz:
#   dyn_need_curl || { emit_result "$BLINDAR_AGENT" "skipped" 0; exit 0; }
dyn_need_curl() {
  command -v curl >/dev/null 2>&1 && return 0
  not_exercised "curl ausente — nenhuma requisicao foi enviada ao sistema"
  log_warn "curl ausente — este check nao conseguiu exercitar nada."
  return 1
}

dyn_need_target() {
  local t
  if ! t=$(dyn_resolve_target); then
    not_exercised "sem alvo: passe --url, exporte BLINDAR_TARGET_URL ou grave .blindar/target.url"
    log_warn "Sem alvo — o sistema no ar nao foi tocado."
    log_info "  Informe com:  --url http://localhost:3000   |   export BLINDAR_TARGET_URL=..."
    return 1
  fi
  DYN_TARGET="$t"
  return 0
}

dyn_need_docker() {
  ensure_docker_up && return 0
  not_exercised "docker indisponivel — nao foi possivel injetar falha nem subir origem externa"
  log_warn "Docker indisponivel — sem injecao de falha, sem origem externa."
  return 1
}

# Autorização explícita, mesma convenção do pentest ativo (.accept-authorization).
# Ataque de origem externa manda tráfego real; sem papel assinado não sai nada.
dyn_need_authorization() {
  local host="$1" auth="${2:-.accept-authorization}"
  if [ ! -f "$auth" ]; then
    not_exercised "sem $auth — origem externa exige autorizacao explicita por escrito"
    log_warn "RECUSADO: sem $auth. Crie com 'authorized: yes' + 'scope: <hosts>'."
    return 1
  fi
  if ! grep -qiE "^authorized:[[:space:]]*(yes|true|sim)" "$auth" 2>/dev/null; then
    not_exercised "$auth nao confirma autorizacao (authorized: yes ausente)"
    log_warn "RECUSADO: $auth sem 'authorized: yes'."
    return 1
  fi
  local scope in_scope=0 s
  scope=$(grep -iE "^(scope|host|target)s?:" "$auth" 2>/dev/null | sed -E 's/^[^:]+:[[:space:]]*//' | tr ',' ' ')
  for s in $scope; do [ "$s" = "$host" ] && in_scope=1; done
  if [ "$in_scope" -eq 0 ]; then
    not_exercised "alvo '$host' fora do escopo autorizado ($scope)"
    log_warn "RECUSADO: '$host' fora do escopo ($scope)."
    return 1
  fi
  return 0
}

# ─── Medição HTTP ───
# Devolve "codigo tempo_ms". Timeout vira código 000 COM o tempo do teto —
# requisição que pendurou É o dado, não um erro a ser descartado. Foi
# exatamente esse dado (health pendurando 45s) que apontou o único P1 da sessão
# que originou esta camada.
dyn_probe() { # url [timeout_s] → "code ms"
  local url="$1" to="${2:-10}" out code ms
  out=$(curl -s -o /dev/null -w '%{http_code} %{time_total}' --max-time "$to" "$url" 2>/dev/null) || out=""
  if [ -z "$out" ]; then echo "000 $((to * 1000))"; return 0; fi
  code=$(echo "$out" | awk '{print $1}')
  ms=$(echo "$out" | awk '{printf "%d", $2 * 1000}')
  [ -z "$code" ] && code="000"
  [ -z "$ms" ] && ms=$((to * 1000))
  echo "$code $ms"
}

# Corpo + código, para inspecionar o que o CLIENTE vê, não só o status.
dyn_probe_body() { # url [timeout_s] [args extras do curl...] → corpo + marcador
  local url="$1" to="${2:-10}"
  shift 2 2>/dev/null || true
  curl -s -w '\n<<<CODE>>>%{http_code}' --max-time "$to" "$@" "$url" 2>/dev/null \
    || printf '\n<<<CODE>>>000'
}

dyn_code_of() { printf '%s' "$1" | sed -n 's/.*<<<CODE>>>\([0-9]*\).*/\1/p' | tail -1; }
dyn_body_of() { printf '%s' "$1" | sed 's/<<<CODE>>>[0-9]*$//'; }

# ─── Percentis ───
# Lê uma amostra de inteiros (ms), um por linha, na entrada padrão.
# Ecoa "p50 p95 p99 max n". Amostra vazia devolve tudo zero E n=0 — quem chama
# precisa distinguir "medi e deu zero" de "nao medi nada". Um p95 de 0 sem essa
# distincao seria o melhor numero possivel vindo de nenhuma medicao.
dyn_percentiles() {
  sort -n | awk '
    { v[NR] = $1 }
    END {
      n = NR
      if (n == 0) { print "0 0 0 0 0"; exit }
      i50 = int(n * 0.50); if (i50 < 1) i50 = 1
      i95 = int(n * 0.95); if (i95 < 1) i95 = 1
      i99 = int(n * 0.99); if (i99 < 1) i99 = 1
      print v[i50], v[i95], v[i99], v[n], n
    }'
}

# ─── Injeção de falha em container ───
# docker pause congela o processo sem matá-lo: o socket fica aberto e ninguém
# recebe RST. É o modo de falha que mais dói e o que os testes quase nunca
# cobrem — matar o container devolve "connection refused" na hora, que o código
# trata; congelar devolve silêncio, que o código costuma esperar para sempre.
#
# dyn_freeze/dyn_unfreeze são SEMPRE usados em par, com trap: deixar um
# container pausado é estragar a máquina de quem rodou o check.
DYN_FROZEN=""

dyn_find_container() { # padrão → nome do container, ou vazio
  local pat="$1"
  docker ps --format '{{.Names}}' 2>/dev/null | grep -iE "$pat" | head -1
}

dyn_freeze() {
  local c="$1"
  docker pause "$c" >/dev/null 2>&1 || return 1
  DYN_FROZEN="$c"
  trap dyn_unfreeze_all EXIT INT TERM
  return 0
}

dyn_unfreeze() {
  local c="${1:-$DYN_FROZEN}"
  [ -z "$c" ] && return 0
  docker unpause "$c" >/dev/null 2>&1 || true
  [ "$c" = "$DYN_FROZEN" ] && DYN_FROZEN=""
  return 0
}

# Idempotente e à prova de Ctrl+C: o container do operador não fica congelado
# porque o check morreu no meio.
dyn_unfreeze_all() {
  if [ -n "$DYN_FROZEN" ]; then
    docker unpause "$DYN_FROZEN" >/dev/null 2>&1 || true
  fi
  DYN_FROZEN=""
}

# ─── Origem externa ───
# Roda um comando DENTRO da rede do alvo, a partir de um container efêmero.
# Bater do mesmo host esconde defeito de fronteira: o proxy reverso, o bind da
# porta e o tratamento de X-Forwarded-For só se revelam quando a requisição
# chega de outro endereço.
DYN_CURL_IMAGE="${DYN_CURL_IMAGE:-curlimages/curl:8.11.1}"

dyn_net_of_container() { # container → primeira rede
  docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' "$1" 2>/dev/null \
    | awk '{print $1}'
}

dyn_curl_from_network() { # rede url [args do curl...] → corpo + marcador
  local net="$1" url="$2"
  shift 2 2>/dev/null || true
  docker run --rm --network "$net" "$DYN_CURL_IMAGE" \
    -s -w '\n<<<CODE>>>%{http_code}' --max-time 10 "$@" "$url" 2>/dev/null \
    || printf '\n<<<CODE>>>000'
}

# ─── Espera ativa ───
# Aguarda o alvo voltar a responder e devolve quantos ms levou. Teto obrigatório:
# espera sem teto vira check que nunca termina.
dyn_wait_recovery() { # url teto_s → ms ate responder, ou -1 se nao voltou
  local url="$1" limit="${2:-60}" waited=0 r code
  while [ "$waited" -lt "$((limit * 1000))" ]; do
    r=$(dyn_probe "$url" 3); code=$(echo "$r" | awk '{print $1}')
    case "$code" in 2*|3*) echo "$waited"; return 0 ;; esac
    sleep 1; waited=$((waited + 1000))
  done
  echo "-1"
  return 1
}

# ─── Escolha SEGURA da dependência a congelar ───
# Encontrado ao exercitar o próprio check: `dyn_find_container "postgres|redis|..."`
# casa com QUALQUER container da máquina. Rodando contra um alvo de teste em
# localhost:8799, ele congelou um redis de outro projeto do operador — um check
# de resiliência causando o incidente que deveria estar medindo.
#
# A regra agora é: só congela o que está amarrado ao alvo.
#   1. --service explícito → o operador escolheu, respeita
#   2. senão → acha o container que PUBLICA a porta do alvo, lê o projeto
#      compose dele, e só considera dependências do MESMO projeto
#   3. sem conseguir amarrar → devolve 1 (o check vira not_exercised)
#
# Ficar sem congelar nada é um resultado ruim. Congelar o container errado é
# pior: quem roda um check não espera que ele derrube o que não é dele.
dyn_app_container_for_port() { # porta → container que publica essa porta
  local port="$1"
  [ -z "$port" ] && return 1
  docker ps --format '{{.Names}}|{{.Ports}}' 2>/dev/null \
    | grep -E "(^|[^0-9])${port}->" \
    | head -1 | cut -d'|' -f1
}

dyn_compose_project_of() { # container → label do projeto compose (ou vazio)
  docker inspect -f '{{index .Config.Labels "com.docker.compose.project"}}' "$1" 2>/dev/null \
    | grep -v '^<no value>$'
}

# Devolve o container em DYN_DEP (variavel), NAO por stdout.
#
# A primeira versao ecoava o nome, e quem chamava fazia
# DEP=$(dyn_pick_dependency ...). Command substitution roda em SUBSHELL: os
# not_exercised() de dentro setavam a variavel de motivo num processo que morria
# em seguida, e o check reportava o texto generico do declare_dynamic — "nao
# chegou a exercitar nada" — em vez de dizer POR QUE.
#
# Medido contra um compose real: o motivo verdadeiro (o nome do container nao
# casava com o padrao) nunca chegou ao result. O campo existe justamente para
# nao repetir o silencio que ele veio acabar. Retorno por variavel, mesmo shell.
dyn_pick_dependency() { # padrao porta_do_alvo -> 0 com DYN_DEP setado, ou 1 com motivo
  local pat="$1" port="${2:-}"
  DYN_DEP=""

  if [ -n "$DYN_SERVICE" ]; then
    DYN_DEP=$(dyn_find_container "$DYN_SERVICE")
    if [ -z "$DYN_DEP" ]; then
      not_exercised "nenhum container casou com --service '$DYN_SERVICE'"
      return 1
    fi
    return 0
  fi

  local app proj
  app=$(dyn_app_container_for_port "$port")
  if [ -z "$app" ]; then
    not_exercised "nenhum container publica a porta $port do alvo — nao da para amarrar dependencia ao alvo com seguranca; passe --service <nome> para escolher explicitamente"
    return 1
  fi
  proj=$(dyn_compose_project_of "$app")
  if [ -z "$proj" ]; then
    not_exercised "container '$app' nao pertence a um projeto compose — sem esse vinculo, congelar por padrao de nome atingiria containers de outros projetos; passe --service <nome>"
    return 1
  fi

  # Casa contra NOME **e IMAGEM**. Um servico chamado `db` rodando
  # `redis:7-alpine` nao tem "redis" no nome — e esse e o nome mais comum em
  # compose real. Casar so por nome deixava o experimento sem alvo justamente no
  # caso tipico, e o check saia sem medir por um detalhe de nomenclatura.
  DYN_DEP=$(docker ps --filter "label=com.docker.compose.project=$proj" --format '{{.Names}}|{{.Image}}' 2>/dev/null | grep -iE "$pat" | head -1 | cut -d'|' -f1)
  if [ -z "$DYN_DEP" ]; then
    local vistos
    vistos=$(docker ps --filter "label=com.docker.compose.project=$proj" --format '{{.Names}} ({{.Image}})' 2>/dev/null | tr '\n' ' ')
    not_exercised "projeto compose '$proj' nao tem dependencia casando com o padrao — containers vistos: ${vistos:-nenhum}"
    return 1
  fi

  # O proprio alvo nunca e a dependencia dele mesmo: congela-lo mediria a
  # aplicacao parada, nao a dependencia caindo.
  if [ "$DYN_DEP" = "$app" ]; then
    not_exercised "o unico candidato e o proprio container da aplicacao ('$app')"
    DYN_DEP=""
    return 1
  fi
  return 0
}

# Porta do alvo, para amarrar container à URL. Sem porta explícita, deduz do
# esquema (80/443) em vez de devolver vazio e cair no caminho inseguro.
dyn_port_of_target() { # url → porta
  local u="$1" p
  p=$(printf '%s' "$u" | sed -nE 's#^[a-z]+://[^/:]+:([0-9]+).*#\1#p')
  if [ -z "$p" ]; then
    case "$u" in https://*) p=443 ;; *) p=80 ;; esac
  fi
  echo "$p"
}
