#!/usr/bin/env bash
# blindar ataque — recon PASSIVO externo via URL.
#   • só GET/HEAD/OPTIONS, rate 1 req/3s, UA de browser
#   • zero payload de ataque → não dispara WAF, não ban
#   • normaliza saída pra findings.json (schema do blindar)
#
# Uso:
#   scripts/attack-recon.sh --url https://seu-site.com \
#     [--out .blindar/findings.attack.json] [--user-agent "..."]
set -uo pipefail

URL=""
OUT=".blindar/findings.attack.json"
UA='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36'
while [[ $# -gt 0 ]]; do case "$1" in
  --url) URL="$2"; shift 2 ;;
  --out) OUT="$2"; shift 2 ;;
  --user-agent) UA="$2"; shift 2 ;;
  -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
  *) echo "arg desconhecido: $1" >&2; exit 2 ;;
esac; done
[[ -z "$URL" ]] && { echo "ERRO: --url obrigatório" >&2; exit 2; }

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$(dirname "$OUT")"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
step(){ printf '[recon] %s\n' "$1"; }

# rate limiter: 1 req / 3s (residencial-like)
gentle_get(){ sleep 3; curl -sS -o "$1" -D "$1.hdr" -A "$UA" --max-time 10 "$2" || true; }

HOST="$(echo "$URL" | sed -E 's#^https?://##; s#/.*$##')"

# 1. headers da home
step "GET $URL (headers)"; gentle_get "$TMP/home" "$URL"

# 2. arquivos esquecidos (só 1 request cada, paths clássicos)
FORGOTTEN_PATHS=(".env" ".git/config" ".git/HEAD" ".DS_Store" "backup.zip" "backup.tar.gz" "database.sql" "phpinfo.php" ".well-known/security.txt" "robots.txt" "sitemap.xml")
for p in "${FORGOTTEN_PATHS[@]}"; do
  step "GET $URL/$p"
  gentle_get "$TMP/f_$(echo "$p" | tr '/.' '__')" "$URL/$p"
done

# 3. endpoints debug conhecidos
DEBUG_PATHS=("actuator/env" "actuator/health" "api-docs" "swagger" "debug" "_next/data")
for p in "${DEBUG_PATHS[@]}"; do
  step "GET $URL/$p"
  gentle_get "$TMP/d_$(echo "$p" | tr '/.' '__')" "$URL/$p"
done

# 4. TLS/cert (1 handshake, sem HTTP)
step "TLS/cert"
if command -v openssl >/dev/null 2>&1; then
  echo | openssl s_client -connect "$HOST:443" -servername "$HOST" -showcerts 2>/dev/null > "$TMP/tls.txt" || true
fi

# 5. DNS/CT (subdomínios via cert público — não bate no servidor)
step "certificate transparency (crt.sh)"
sleep 3
curl -sS -A "$UA" --max-time 15 "https://crt.sh/?q=%25.${HOST}&output=json" -o "$TMP/crt.json" || true

# 6. normaliza tudo em findings.json
step "normalizando findings"
node "$ROOT/scripts/attack-recon-report.js" --dir "$TMP" --url "$URL" --out "$OUT"

step "concluído: $OUT"
