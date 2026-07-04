#!/usr/bin/env bash
# blindar-learn — transforma um INCIDENTE em check + par de fixture + entrada no
# gate de self-test. Automatiza o processo que antes era manual: todo bug real
# achado num projeto vira um check permanente que impede a recorrência.
#
# Uso: bash scripts/blindar-learn.sh --name <kebab-case> [--sev high|crit|med|low] [--desc "..."]
#
# Gera (já verde no gate, com marcador placeholder pra você substituir):
#   templates/checks/check-<name>.sh          (esqueleto determinístico)
#   tests/fixtures/project-<name>-bad/        (dispara)
#   tests/fixtures/project-<name>-good/       (cala)
#   + linha em scripts/check-selftest.sh (PAIRS)
#
# Depois: edite o padrão real + as fixtures, rode `bash scripts/check-selftest.sh`.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"
CHECKS="$SKILL_DIR/templates/checks"
FIX="$SKILL_DIR/tests/fixtures"
SELFTEST="$SCRIPT_DIR/check-selftest.sh"

NAME=""; SEV="high"; DESC=""
while [ $# -gt 0 ]; do
  case "$1" in
    --name) NAME="$2"; shift 2 ;;
    --sev) SEV="$2"; shift 2 ;;
    --desc) DESC="$2"; shift 2 ;;
    *) shift ;;
  esac
done

[ -z "$NAME" ] && { echo "ERRO: --name <kebab-case> é obrigatório" >&2; exit 64; }
# sanitiza pra kebab-case
NAME=$(echo "$NAME" | tr '[:upper:] _' '[:lower:]--' | sed 's/[^a-z0-9-]//g; s/--*/-/g; s/^-//; s/-$//')
[ -z "$NAME" ] && { echo "ERRO: nome inválido" >&2; exit 64; }
[ -z "$DESC" ] && DESC="TODO: descrever o que este check detecta"
case "$SEV" in crit|high|med|low) ;; *) echo "ERRO: --sev deve ser crit|high|med|low" >&2; exit 64 ;; esac

CHECK="$CHECKS/check-$NAME.sh"
[ -f "$CHECK" ] && { echo "ERRO: $CHECK já existe" >&2; exit 65; }

# 1. Esqueleto do check (verde de saída: casa o marcador; você troca pela lógica real)
cat > "$CHECK" <<CHECKEOF
#!/usr/bin/env bash
# Materializa: $NAME — $DESC
# Nascido de incidente (ver docs/INCIDENT-TO-CHECK.md). TODO: troque o padrão
# BLINDAR_INCIDENT_MARKER pela detecção real do bug.
BLINDAR_AGENT="check-$NAME"
source "\$(dirname "\$0")/_lib.sh"
log_section "Check: $NAME"

if ! command -v rg >/dev/null 2>&1; then emit_result "\$BLINDAR_AGENT" "skipped" 0; exit 0; fi
IGNORE=(-g '!node_modules' -g '!dist' -g '!.git' -g '!**/*.test.*')
FAIL=0

# TODO: substitua "BLINDAR_INCIDENT_MARKER" pelo padrão real que reproduz o bug.
HITS=\$(rg -c "BLINDAR_INCIDENT_MARKER" "\${IGNORE[@]}" 2>/dev/null | wc -l)
if [ "\$HITS" -gt 0 ]; then
  add_finding "$SEV" "$DESC" "" ""
  FAIL=1
fi

if [ "\$FAIL" -eq 1 ]; then emit_result "\$BLINDAR_AGENT" "failed" 1; exit 1; fi
emit_result "\$BLINDAR_AGENT" "passed" 0
CHECKEOF

# 2. Fixtures (bad dispara, good cala) — placeholders neutros
mkdir -p "$FIX/project-$NAME-bad" "$FIX/project-$NAME-good"
printf 'BLINDAR_INCIDENT_MARKER\n' > "$FIX/project-$NAME-bad/incident.txt"
printf 'tudo certo aqui\n' > "$FIX/project-$NAME-good/clean.txt"

# 3. Insere par no gate (antes do sentinel) via node — evita escaping de sed
if command -v node >/dev/null 2>&1; then
  node -e '
    const fs=require("fs"); const f=process.argv[1]; const name=process.argv[2];
    const line = `  "check-${name}.sh | project-${name}-bad | project-${name}-good"`;
    let s=fs.readFileSync(f,"utf8");
    if(!s.includes(`check-${name}.sh |`)){
      s=s.replace(/(\n\s*# blindar-learn:insert)/, `\n${line}$1`);
      fs.writeFileSync(f,s);
    }
  ' "$SELFTEST" "$NAME"
fi

echo "✓ criado check-$NAME.sh + fixtures + par no gate."
echo ""
echo "Próximos passos:"
echo "  1. Edite $CHECK — troque BLINDAR_INCIDENT_MARKER pela detecção real."
echo "  2. Edite as fixtures pra reproduzir o incidente (bad) e o estado correto (good)."
echo "  3. Rode: bash scripts/check-selftest.sh   (o par tem que dar dispara+cala)."
echo "  4. Adicione check-$NAME ao pipeline/MODULE-MAP.json no módulo apropriado."
