#!/usr/bin/env bash
# Materializa: environment-parity — o ambiente de teste roda a MESMA engine de
# banco que dev e produção?
#
# Bug real que originou o check: DEV=PostgreSQL, TEST=SQLite, PROD=PostgreSQL.
# A suite fica verde porque SQLite aceita o que o Postgres recusa — tipos frouxos,
# sem checagem de FK por default, sem tipos nativos de data/hora com timezone.
# O bug só aparece em produção, e a suite verde é justamente o que dá confiança
# para promover. Divergência de engine entre ambientes é falso-verde estrutural.
#
# Bash 3.2 compat: sem declare -A (macOS default não tem array associativo).
BLINDAR_AGENT="check-environment-parity"
source "$(dirname "$0")/_lib.sh"
log_section "Check: paridade de ambientes (dev × test × prod)"

# Classifica o valor de uma connection string em engine canônica.
engine_of_value() {
  case "$1" in
    *postgres*|*postgis*) echo "postgresql" ;;
    *mysql*|*mariadb*)    echo "mysql" ;;
    *mongodb*)            echo "mongodb" ;;
    *sqlite*|*file:*)     echo "sqlite" ;;
    *)                    echo "" ;;
  esac
}

# Extrai a engine declarada num arquivo de env.
engine_of_file() {
  local f="$1" line
  [ -f "$f" ] || return 0
  line=$(grep -hE '^[[:space:]]*(export[[:space:]]+)?(DATABASE_URL|DB_URL|SQLALCHEMY_DATABASE_URI|DJANGO_DATABASE_URL|POSTGRES_URL)[[:space:]]*=' "$f" 2>/dev/null | head -1)
  [ -z "${line:-}" ] && return 0
  engine_of_value "$line"
}

# Nome canônico do ambiente a partir do nome do arquivo.
env_of_file() {
  case "$(basename "$1")" in
    .env.test|.env.testing|.env.ci)      echo "test" ;;
    .env.staging|.env.homolog)           echo "staging" ;;
    .env.production|.env.prod)           echo "production" ;;
    .env.development|.env.dev)           echo "development" ;;
    .env|.env.example|.env.sample|.env.local) echo "default" ;;
    *) echo "" ;;
  esac
}

CANDIDATES=".env .env.example .env.sample .env.local .env.development .env.dev .env.test .env.testing .env.ci .env.staging .env.homolog .env.production .env.prod"

PAIRS=""      # "ambiente=engine;..." acumulado
ENGINES=""    # engines distintas vistas, separadas por espaço
FOUND=0

for f in $CANDIDATES; do
  [ -f "$f" ] || continue
  eng=$(engine_of_file "$f")
  [ -z "${eng:-}" ] && continue
  envname=$(env_of_file "$f")
  [ -z "${envname:-}" ] && continue
  FOUND=$((FOUND+1))
  PAIRS="${PAIRS}${envname}(${f})=${eng};"
  case " $ENGINES " in
    *" $eng "*) : ;;
    *) ENGINES="$ENGINES $eng" ;;
  esac
done

# Sem env declarando banco, ou só um ambiente → nada a comparar.
if [ "$FOUND" -lt 2 ]; then
  log_info "menos de 2 ambientes declaram banco — nada a comparar (skipped)"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

DISTINCT=$(echo "$ENGINES" | tr ' ' '\n' | grep -c '[a-z]' | tail -1)
DISTINCT=$(echo "$DISTINCT" | tr -d ' ')

if [ "$DISTINCT" -gt 1 ]; then
  log_fail "ENVIRONMENT DRIFT: $DISTINCT engines de banco distintas entre ambientes"
  log_info "  $PAIRS"
  add_finding "high" "paridade de ambientes quebrada: engines distintas entre ambientes — ${PAIRS%;}. Suite verde em SQLite não prova comportamento em PostgreSQL (tipos, FK, timezone divergem)" ".env*" ""
else
  log_pass "todos os $FOUND ambientes declaram a mesma engine ($(echo "$ENGINES" | xargs))"
fi

# ─── Deriva de VERSÃO da mesma engine entre arquivos de compose ───
if command -v rg >/dev/null 2>&1; then
  COMPOSE_TMP=$(mktemp)
  rg -n -o -i 'image:[[:space:]]*["'"'"']?(docker\.io/)?(library/)?postgres:[0-9]+' \
    -g '!node_modules' -g '!.git' -g '!.blindar' > "$COMPOSE_TMP" 2>/dev/null || true
  VERSIONS=$(sed -E 's/.*postgres:([0-9]+).*/\1/' "$COMPOSE_TMP" 2>/dev/null | sort -u | tr '\n' ' ')
  VCOUNT=$(echo "$VERSIONS" | tr ' ' '\n' | grep -c '[0-9]' | tail -1)
  VCOUNT=$(echo "$VCOUNT" | tr -d ' ')
  if [ "$VCOUNT" -gt 1 ]; then
    add_finding "med" "versões distintas de PostgreSQL entre arquivos de compose ($(echo "$VERSIONS" | xargs)) — comportamento de query planner e sintaxe podem divergir entre ambientes" "docker-compose*.yml" ""
    log_warn "deriva de versão do Postgres: $VERSIONS"
  fi
  rm -f "$COMPOSE_TMP"
fi

if [ "${#FINDINGS[@]}" -gt 0 ]; then
  emit_result "$BLINDAR_AGENT" "failed" 1
  exit 1
fi

emit_result "$BLINDAR_AGENT" "passed" 0
exit 0
