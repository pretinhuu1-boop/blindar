#!/usr/bin/env bash
# Instala no Claude Code: o guard da lista CRITICAL (hook PreToolUse) e, opcional,
# a allowlist de permissões do blindar.
#
# LÊ ANTES DE ESCREVER e faz MERGE. settings.json costuma ter configuração do
# operador; substituir o arquivo apagaria hooks e permissões que já estavam lá.
#
# Uso (na pasta do projeto, ou em qualquer lugar para escopo global):
#   bash ~/.claude/skills/blindar/scripts/install-hooks.sh            # projeto
#   bash ~/.claude/skills/blindar/scripts/install-hooks.sh --user     # global
#   bash ~/.claude/skills/blindar/scripts/install-hooks.sh --no-allowlist
#
# Exit: 0 = instalado (ou já estava) | 1 = falha | 70 = sem node

set -uo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ESCOPO="projeto"
ALLOWLIST=1
SO_CLAUDE_MD=0
for a in "$@"; do
  case "$a" in
    --user) ESCOPO="user" ;;
    --no-allowlist) ALLOWLIST=0 ;;
    --claude-md) SO_CLAUDE_MD=1 ;;
    -h|--help) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  esac
done

command -v node >/dev/null 2>&1 || {
  echo "ERRO: node requerido para editar settings.json com segurança (merge, não substituição)." >&2
  exit 70
}

if [ "$ESCOPO" = "user" ]; then
  ALVO="$HOME/.claude/settings.json"
else
  ALVO=".claude/settings.json"
fi
mkdir -p "$(dirname "$ALVO")"
[ -f "$ALVO" ] || echo '{}' > "$ALVO"

GUARD="$SKILL_DIR/templates/hooks/blindar-guard.sh"
[ -f "$GUARD" ] || { echo "ERRO: guard não encontrado em $GUARD" >&2; exit 1; }

node -e '
const fs = require("fs");
const alvo = process.argv[1], guard = process.argv[2], comAllowlist = process.argv[3] === "1";

let cfg;
try { cfg = JSON.parse(fs.readFileSync(alvo, "utf8") || "{}"); }
catch (e) {
  // settings.json malformado desativa TODAS as configurações daquele arquivo em
  // silêncio. Parar aqui é melhor que sobrescrever o que o operador escreveu.
  console.error("ERRO: " + alvo + " não é JSON válido — corrija antes. Nada foi alterado.");
  process.exit(1);
}

const comando = "bash " + JSON.stringify(guard).slice(1, -1);
cfg.hooks = cfg.hooks || {};
cfg.hooks.PreToolUse = Array.isArray(cfg.hooks.PreToolUse) ? cfg.hooks.PreToolUse : [];

const jaTem = cfg.hooks.PreToolUse.some((e) =>
  (e.hooks || []).some((h) => typeof h.command === "string" && h.command.includes("blindar-guard")));

if (jaTem) {
  console.log("  guard já instalado em " + alvo);
} else {
  cfg.hooks.PreToolUse.push({
    matcher: "Bash",
    hooks: [{
      type: "command",
      command: comando,
      timeout: 10,
      statusMessage: "blindar: checando lista CRITICAL"
    }]
  });
  console.log("  guard adicionado (PreToolUse/Bash)");
}

if (comAllowlist) {
  // Só leitura. Nada que altere estado entra aqui — allowlist existe para tirar
  // atrito de comando inofensivo, não para pular decisão que importa.
  const RECOMENDADAS = [
    "Bash(git status)", "Bash(git diff *)", "Bash(git log *)", "Bash(git branch *)",
    "Bash(node --version)", "Bash(npm --version)",
    "Read", "Glob", "Grep"
  ];
  cfg.permissions = cfg.permissions || {};
  cfg.permissions.allow = Array.isArray(cfg.permissions.allow) ? cfg.permissions.allow : [];
  const antes = cfg.permissions.allow.length;
  for (const r of RECOMENDADAS) if (!cfg.permissions.allow.includes(r)) cfg.permissions.allow.push(r);
  const novas = cfg.permissions.allow.length - antes;
  console.log(novas ? "  allowlist: +" + novas + " regra(s) só-leitura" : "  allowlist: já completa");
}

fs.writeFileSync(alvo, JSON.stringify(cfg, null, 2) + "\n", "utf8");
' "$ALVO" "$GUARD" "$ALLOWLIST" || exit 1

# ─── CLAUDE.md de exemplo (opcional, sempre pergunta) ───
# Governança global é do OPERADOR. Instalar por cima sem perguntar seria
# reescrever a forma de trabalhar de alguém — por isso pergunta, e por isso
# guarda backup datado quando já existe um.
MODELO="$SKILL_DIR/templates/CLAUDE.md.exemplo"
DESTINO_MD="$HOME/.claude/CLAUDE.md"
if [ -f "$MODELO" ]; then
  echo ""
  if [ -f "$DESTINO_MD" ]; then
    echo "  Você já tem um ~/.claude/CLAUDE.md. O blindar traz um modelo com os"
    echo "  anti-padrões que este projeto pagou caro para aprender."
    PERGUNTA="  Substituir pelo modelo? (backup datado do seu é feito antes) [s/N] "
  else
    echo "  O blindar traz um CLAUDE.md de exemplo: governança, anti-padrões e"
    echo "  regras de qualidade que valem para qualquer projeto."
    PERGUNTA="  Instalar em ~/.claude/CLAUDE.md? [s/N] "
  fi
  if [ "${BLINDAR_INSTALL_CLAUDE_MD:-ask}" = "yes" ]; then RESP_MD="s"
  elif [ "${BLINDAR_INSTALL_CLAUDE_MD:-ask}" = "no" ] || [ ! -t 0 ]; then RESP_MD="n"
  else printf '%s' "$PERGUNTA"; read -r RESP_MD </dev/tty || RESP_MD="n"; fi
  case "${RESP_MD:-n}" in
    s|S|y|Y)
      mkdir -p "$(dirname "$DESTINO_MD")"
      if [ -f "$DESTINO_MD" ]; then
        BKP="$DESTINO_MD.backup-$(date -u +%Y-%m-%d)"
        cp "$DESTINO_MD" "$BKP" && echo "  backup: $BKP"
      fi
      cp "$MODELO" "$DESTINO_MD" && echo "  CLAUDE.md instalado em $DESTINO_MD" ;;
    *) echo "  pulado. Depois: cp \"$MODELO\" \"$DESTINO_MD\"" ;;
  esac
fi

echo ""
echo "  Arquivo: $ALVO"
echo ""
echo "  O guard PAUSA (não bloqueia) comandos da lista CRITICAL do risk-engine:"
echo "  DROP/TRUNCATE, DELETE sem WHERE, migrate reset, push --force,"
echo "  reset --hard, reescrita de histórico, rm -rf em raiz, remover volume."
echo ""
echo "  Pausa e não proibição porque a regra é PEDIR AUTORIZAÇÃO: proibir tornaria"
echo "  impossível o trabalho legítimo, e o operador desligaria o hook inteiro."
echo ""
echo "  Se o hook não disparar de primeira, abra /hooks uma vez (recarrega a config)."
