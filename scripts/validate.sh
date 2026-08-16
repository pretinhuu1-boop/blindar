#!/usr/bin/env bash
# scripts/validate.sh
#
# Valida um arquivo JSON contra um schema do blindar.
# Wrapper minimo — checa estrutura basica.
# Pra validacao completa: instale ajv-cli ou python jsonschema.
#
# Uso:
#   ./validate.sh inventory output.json
#   ./validate.sh state .blindar/state.json

set -u

if [ $# -lt 2 ]; then
  echo "Uso: $0 <schema> <file>"
  echo ""
  echo "Schemas disponiveis:"
  SKILL_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
  for f in "$SKILL_ROOT"/schemas/*.schema.json; do
    name=$(basename "$f" .schema.json)
    echo "  - $name"
  done
  exit 2
fi

SCHEMA_NAME="$1"
FILE="$2"
SKILL_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCHEMA="$SKILL_ROOT/schemas/${SCHEMA_NAME}.schema.json"

[ -f "$SCHEMA" ] || { echo "[FAIL] Schema nao encontrado: $SCHEMA"; exit 1; }
[ -f "$FILE" ]   || { echo "[FAIL] Arquivo nao encontrado: $FILE"; exit 1; }

# ─── Path nativo pros validadores ──────────────────────────────────────────
# Em Git Bash/MSYS o `[ -f ]` acima passa (o bash entende /tmp), mas jq e
# python3 sao binarios NATIVOS do Windows: eles resolvem "/tmp/cfg.json" como
# "C:\tmp\cfg.json", que nao existe. Sem esta conversao o ENOENT era engolido
# e o script culpava o CONTEUDO do arquivo. Ver docs/BASH-COMPAT.md.
# `-m` (mixed: C:/Users/...) e aceito tanto pelo bash quanto pelos binarios
# nativos, e nao carrega backslash pra dentro de string de outra linguagem.
to_native() {
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -m "$1" 2>/dev/null || printf '%s' "$1"
  else
    printf '%s' "$1"
  fi
}

FILE_NATIVE=$(to_native "$FILE")
SCHEMA_NATIVE=$(to_native "$SCHEMA")

if [ ! -f "$FILE_NATIVE" ]; then
  echo "[FAIL] Nao consegui abrir $FILE"
  echo "       Path nativo resolvido: $FILE_NATIVE"
  echo "       Problema de path (nao de conteudo) — passe um path que o binario"
  echo "       nativo entenda, ou instale cygpath."
  exit 1
fi

# ─── JSON valido? ──────────────────────────────────────────────────────────
# Separa os dois modos de falha: rc=3 "nao abriu", rc!=0 "conteudo invalido".
# O stderr do validador e preservado e impresso — nunca engolido.
PARSE_ERR=""
PARSE_RC=0
if command -v jq >/dev/null 2>&1; then
  PARSE_ERR=$(jq empty "$FILE_NATIVE" 2>&1) || PARSE_RC=$?
  # jq nao tem exit code estavel pra ENOENT entre versoes: decide pela leitura.
  [ "$PARSE_RC" -ne 0 ] && [ ! -r "$FILE_NATIVE" ] && PARSE_RC=3
elif command -v python3 >/dev/null 2>&1; then
  # Path vai via argv — nunca interpolado no source, senao "C:\tmp\new.json"
  # viraria tab + newline dentro da string Python.
  PARSE_ERR=$(python3 -c 'import json, sys
try:
    raw = open(sys.argv[1], "rb").read()
except OSError as e:
    sys.stderr.write("%s\n" % e); sys.exit(3)
try:
    json.loads(raw.decode("utf-8-sig"))
except Exception as e:
    sys.stderr.write("%s\n" % e); sys.exit(4)' "$FILE_NATIVE" 2>&1) || PARSE_RC=$?
else
  echo "[WARN] sem jq nem python3 — pulando parse check"
fi

if [ "$PARSE_RC" -eq 3 ]; then
  echo "[FAIL] Nao consegui abrir $FILE (path nativo: $FILE_NATIVE)"
  [ -n "$PARSE_ERR" ] && echo "       $PARSE_ERR"
  exit 1
elif [ "$PARSE_RC" -ne 0 ]; then
  echo "[FAIL] JSON invalido em $FILE"
  [ -n "$PARSE_ERR" ] && echo "       $PARSE_ERR"
  exit 1
fi
echo "[OK] JSON parsea sem erro"
echo "[OK] Schema $SCHEMA_NAME encontrado"

# Check required (basico, via jq se disponivel)
if command -v jq >/dev/null 2>&1; then
  required=$(jq -r '.required[]?' "$SCHEMA_NATIVE") || {
    echo "[FAIL] Nao consegui ler .required do schema $SCHEMA_NATIVE"
    exit 1
  }
  missing=""
  for req in $required; do
    # has($k) e o teste correto de "required" e sobrevive a chave com hifen —
    # `.$req` seria erro de sintaxe do jq e viraria "campo ausente" falso.
    if ! jq -e --arg k "$req" 'has($k)' "$FILE_NATIVE" >/dev/null 2>&1; then
      missing="${missing} ${req}"
    fi
  done
  if [ -n "$missing" ]; then
    echo "[FAIL] Campos required ausentes:$missing"
    exit 1
  fi
  echo "[OK] Todos os campos required presentes"
fi

echo ""
echo "Validacao basica OK. Para validacao completa de tipos/enums:"
echo "  npm i -g ajv-cli ajv-formats"
echo "  ajv validate -s \"$SCHEMA_NATIVE\" -d \"$FILE_NATIVE\""
