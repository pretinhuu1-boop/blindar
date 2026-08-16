#!/usr/bin/env bash
# Teste de MÁQUINA LIMPA.
#
# Todo o v0.65–v0.72 foi construído para rodar fora desta máquina e nunca rodou
# fora dela. doctor.sh, install-hooks.sh, sync-skill.sh e o check de atualização
# diária só foram exercitados aqui, onde tudo já estava no lugar. "Funciona em
# outra máquina" é, pelo padrão do próprio blindar, NÃO VERIFICADO.
#
# O que este script isola:
#   HOME novo            → nenhum ~/.claude preexistente, nenhum settings.json
#   clone do GitHub      → prova o que está PUBLICADO, não o que está no disco
#   env BLINDAR_* limpo  → nenhuma config desta sessão vazando
#   projeto-alvo sintético com vulnerabilidade real → o run tem o que achar
#
# O que NÃO isola (e por isso não afirma): PATH e ferramentas do sistema. Uma VM
# de verdade não teria git/node/rg. Aqui isso é medido pelo doctor, não fingido.

set -uo pipefail
BASE="${BLINDAR_LIMPA_DIR:-${TMPDIR:-/tmp}}/blindar-maquina-limpa"
rm -rf "$BASE" 2>/dev/null
mkdir -p "$BASE/home" "$BASE/projeto"

export HOME="$BASE/home"
export USERPROFILE="$BASE/home"
for v in $(env | grep -o '^BLINDAR_[A-Z_]*' || true); do unset "$v"; done
unset ANCORAR_DIR 2>/dev/null

ok=0; falhou=0
passo() { printf '\n\033[1m── %s ──\033[0m\n' "$1"; }
vale()  { if [ "$1" -eq 0 ]; then printf '  \033[32mOK\033[0m   %s\n' "$2"; ok=$((ok+1));
          else printf '  \033[31mFALHA\033[0m %s\n' "$2"; falhou=$((falhou+1)); fi; }

# --local instala a ÁRVORE DE TRABALHO; sem flag, clona do GitHub.
# Os dois medem coisas diferentes e ambos importam: o clone prova o que está
# PUBLICADO (é o que outra máquina recebe hoje), o local prova o que está
# prestes a ser publicado. Passar só no local seria afirmar sobre um artefato
# que ninguém consegue baixar ainda.
mkdir -p "$HOME/.claude/skills"
S="$HOME/.claude/skills/blindar"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ "${1:-}" = "--local" ]; then
  passo "1. instala a ÁRVORE DE TRABALHO local no HOME limpo"
  mkdir -p "$S"
  # git ls-files: leva o que é versionado, e só isso — nada de .blindar/,
  # node_modules ou resto de run anterior contaminando o "limpo".
  ( cd "$REPO" && git ls-files ) | while IFS= read -r f; do
      mkdir -p "$S/$(dirname "$f")"; cp "$REPO/$f" "$S/$f"
    done
else
  passo "1. clone do GitHub para o HOME limpo"
  git clone --quiet --depth 1 https://github.com/pretinhuu1-boop/blindar.git "$S" 2>&1 | tail -2
fi
[ -f "$S/SKILL.md" ] && [ -f "$S/VERSION" ]; vale $? "clone traz SKILL.md e VERSION ($(cat "$S/VERSION" 2>/dev/null))"

passo "2. arquivos que o run precisa vieram no clone"
for f in scripts/blindar-run.sh scripts/doctor.sh templates/checks/_lib.sh \
         templates/checks/_cache.sh pipeline/MODULE-MAP.json; do
  [ -s "$S/$f" ]; vale $? "$f"
done
N_CHECKS=$(find "$S/templates/checks" -maxdepth 1 -name 'check-*.sh' 2>/dev/null | wc -l | tr -d ' ')
[ "$N_CHECKS" -ge 100 ]; vale $? "$N_CHECKS checks no clone"
N_AG=$(find "$S/agents" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
[ "$N_AG" -ge 100 ]; vale $? "$N_AG agentes no clone"

passo "3. doctor num HOME sem nada"
bash "$S/scripts/doctor.sh" > "$BASE/doctor.txt" 2>&1
DRC=$?
[ "$DRC" -le 1 ]; vale $? "doctor termina com exit $DRC (0 ou 1, nunca crash)"
grep -q "ancorar" "$BASE/doctor.txt"; vale $? "doctor menciona o ancorar"
grep -qi "ausente" "$BASE/doctor.txt"; vale $? "doctor acusa ausência no HOME limpo (ancorar não está lá)"
grep -q "scanners externos" "$BASE/doctor.txt"; vale $? "doctor lista os scanners externos"

passo "4. projeto-alvo com vulnerabilidade real"
cd "$BASE/projeto"
git init -q .
git config user.email t@t; git config user.name t
mkdir -p src
cat > package.json <<'EOF'
{ "name": "alvo", "version": "1.0.0", "scripts": { "start": "node src/server.js" } }
EOF
# O segredo do projeto sintético é um JWT de exemplo público do jwt.io: o
# gitleaks detecta (é o ponto — sem detecção o passo 5 não prova nada) e não é
# credencial de provedor, então o Push Protection do GitHub deixa este arquivo
# existir no repositório.
#
# A primeira versão usava uma chave com cara de Stripe e o push foi recusado —
# a mesma proteção que faz o fixture `project-with-secrets` ser mascarado, e que
# foi justamente o motivo de o falso negativo do check-secrets ter vivido tanto.
cat > src/server.js <<'EOF'
const express = require('express');
const app = express();
const SEGREDO = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4ifQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c";
app.get('/u/:id', (req, res) => {
  db.query("SELECT * FROM users WHERE id = " + req.params.id, (e, r) => res.json(r));
});
app.get('/run', (req, res) => { eval(req.query.cmd); res.send('ok'); });
app.listen(3000);
EOF
cat > src/mock.js <<'EOF'
export const salvar = async () => ({ id: "mock-123", ok: true });
console.log("debug: salvando");
EOF
git add -A >/dev/null 2>&1; git commit -qm "init" >/dev/null 2>&1
[ -f src/server.js ]; vale $? "projeto sintético criado (segredo + SQLi + eval + mock)"

passo "5. checks individuais no projeto limpo"
for c in check-secrets check-invisible-unicode check-git-hygiene; do
  [ -f "$S/templates/checks/$c.sh" ] || { vale 1 "$c ausente no clone"; continue; }
  bash "$S/templates/checks/$c.sh" >/dev/null 2>&1
  R="$BASE/projeto/.blindar/results/$c.json"
  if [ -s "$R" ]; then
    ST=$(node -e 'console.log(JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).status)' "$R" 2>/dev/null)
    MT=$(node -e 'const j=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));console.log(j.missing_tool||"-")' "$R" 2>/dev/null)
    printf '       %s → status=%s missing_tool=%s\n' "$c" "$ST" "$MT"
    # skipped só é aceitável se DISSER qual ferramenta faltou
    if [ "$ST" = "skipped" ] && [ "$MT" = "-" ]; then vale 1 "$c: skipped sem dizer o que faltou"
    else vale 0 "$c: result válido"; fi
  else
    vale 1 "$c não gravou result"
  fi
done

passo "6. validação de schema dos results"
node "$S/scripts/validate-schemas.js" --input "$BASE/projeto/.blindar/results" --quiet >/dev/null 2>&1
vale $? "todos os results passam no schema"

passo "7. check de atualização diária"
if [ -f "$S/scripts/check-update.sh" ]; then
  bash "$S/scripts/check-update.sh" > "$BASE/update.txt" 2>&1
  URC=$?
  [ "$URC" -le 1 ]; vale $? "check-update roda sem crash (exit $URC)"
  MARCA=$(find "$HOME/.claude" "$S" -name '*update*' -newermt '-2 minutes' 2>/dev/null | head -3)
  printf '       marca de "já checei hoje": %s\n' "${MARCA:-nenhuma encontrada}"
else
  vale 1 "scripts/check-update.sh ausente no clone"
fi

passo "8. instalador de hooks no HOME limpo"
if [ -f "$S/scripts/install-hooks.sh" ]; then
  BLINDAR_INSTALL_CLAUDE_MD=no bash "$S/scripts/install-hooks.sh" --user > "$BASE/hooks.txt" 2>&1
  vale $? "install-hooks --user roda"
  [ -f "$HOME/.claude/settings.json" ]; vale $? "settings.json criado do zero"
  if [ -f "$HOME/.claude/settings.json" ]; then
    node -e 'JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"))' "$HOME/.claude/settings.json" 2>/dev/null
    vale $? "settings.json é JSON válido"
    grep -q "PreToolUse" "$HOME/.claude/settings.json"; vale $? "hook PreToolUse registrado"
  fi
  [ -f "$HOME/.claude/CLAUDE.md" ] && vale 1 "CLAUDE.md instalado mesmo com resposta 'no'" \
    || vale 0 "CLAUDE.md respeitou a recusa"
else
  vale 1 "install-hooks.sh ausente"
fi

printf '\n\033[1m═══ %d OK, %d FALHA ═══\033[0m\n' "$ok" "$falhou"
printf 'artefatos em: %s\n' "$BASE"
[ "$falhou" -eq 0 ] || exit 1
