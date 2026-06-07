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

# JSON valido?
if command -v jq >/dev/null 2>&1; then
  if ! jq empty "$FILE" 2>/dev/null; then
    echo "[FAIL] JSON invalido em $FILE"
    exit 1
  fi
elif command -v python3 >/dev/null 2>&1; then
  if ! python3 -c "import json; json.load(open('$FILE'))" 2>/dev/null; then
    echo "[FAIL] JSON invalido em $FILE"
    exit 1
  fi
else
  echo "[WARN] sem jq nem python3 — pulando parse check"
fi
echo "[OK] JSON parsea sem erro"
echo "[OK] Schema $SCHEMA_NAME encontrado"

# Check required (basico, via jq se disponivel)
if command -v jq >/dev/null 2>&1; then
  required=$(jq -r '.required[]?' "$SCHEMA" 2>/dev/null)
  missing=""
  for req in $required; do
    if ! jq -e ".$req" "$FILE" >/dev/null 2>&1; then
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
echo "  ajv validate -s $SCHEMA -d $FILE"
