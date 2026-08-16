#!/usr/bin/env bash
# blindar guard — hook PreToolUse do Claude Code para a lista CRITICAL do
# risk-engine.
#
# POR QUE EXISTE. O `agents/risk-engine.md` diz que apagar dado, desligar
# autenticação e reescrever histórico compartilhado pausam e pedem autorização
# mesmo em modo AUTO. Hoje isso depende de o modelo LEMBRAR. O seu CLAUDE.md já
# tem a regra: "Claude pode esquecer de executar algo. Hook não esquece."
#
# O QUE FAZ. Lê o JSON do PreToolUse no stdin, olha o comando, e devolve
# `permissionDecision: "ask"` quando ele casa a lista — o operador decide.
#
# POR QUE "ask" E NÃO "deny". A regra do risk-engine é PAUSAR, não proibir para
# sempre. `deny` tornaria impossível o trabalho legítimo (migração planejada,
# rotação de credencial, decommission autorizado) e o operador acabaria
# desligando o hook inteiro — trocando uma pausa por nenhuma proteção.
#
# FALHA ABERTA, DE PROPÓSITO. Sem `node` o guard libera com aviso. Um guard que
# bloqueia TODO comando porque uma dependência sumiu é pior que não ter guard:
# o operador desinstala no primeiro minuto. Esta é defesa em profundidade — o
# playbook do risk-engine continua valendo por cima.
#
# Instalar: bash scripts/install-hooks.sh

set -uo pipefail

PAYLOAD=$(cat 2>/dev/null || echo '{}')

liberar() { printf '%s\n' '{}'; exit 0; }

command -v node >/dev/null 2>&1 || {
  printf '%s\n' '{"systemMessage":"blindar-guard inativo: node ausente. A lista CRITICAL nao esta sendo verificada."}'
  exit 0
}

printf '%s' "$PAYLOAD" | node -e '
let bruto = "";
process.stdin.on("data", (d) => (bruto += d));
process.stdin.on("end", () => {
  let ev;
  try { ev = JSON.parse(bruto); } catch (e) { process.stdout.write("{}"); return; }
  const cmd = String(ev?.tool_input?.command ?? "");
  if (!cmd.trim()) { process.stdout.write("{}"); return; }

  // Cada regra diz O QUE SE PERDE, nao so "perigoso". Uma pausa sem o custo
  // explicito vira clique reflexo em "sim" — que e o mesmo que nao pausar.
  const REGRAS = [
    [/\bDROP\s+(TABLE|SCHEMA|DATABASE)\b/i,
     "DROP de tabela/schema/banco: o dado deixa de existir. Restaurar exige backup, e backup nunca restaurado e hipotese."],
    [/\bTRUNCATE\s+/i,
     "TRUNCATE apaga todas as linhas e nao dispara trigger de auditoria."],
    [/\bDELETE\s+FROM\b(?![\s\S]*\bWHERE\b)/i,
     "DELETE sem WHERE apaga a tabela inteira."],
    [/\b(migrate\s+reset|db\s+push\s+--force-reset|prisma\s+migrate\s+reset)\b/i,
     "reset de migration recria o banco do zero: todo dado local vai junto."],
    [/\bDROP\s+COLUMN\b/i,
     "DROP COLUMN e irreversivel: reverter o deploy traz o codigo de volta, nao o dado."],
    [/git\s+push\b[\s\S]*--force(?!-with-lease)/i,
     "push --force sobrescreve o trabalho de quem publicou depois de voce. --force-with-lease recusa nesse caso."],
    [/git\s+reset\s+--hard\b/i,
     "reset --hard descarta o working tree sem passar pelo reflog do que nao foi commitado."],
    [/git\s+(filter-branch|filter-repo)\b/i,
     "reescrever historico obriga todo mundo a reclonar, e nao remove o segredo dos clones ja feitos."],
    [/\brm\s+-[a-z]*[rf][a-z]*\s+[\/~]/i,
     "rm -rf em caminho de raiz ou home."],
    [/\bdocker\s+(volume\s+rm|compose\s+down\s+[\s\S]*(-v|--volumes))/i,
     "remover volume apaga o dado persistente do banco, nao so o container."],
    [/\b(DROP|ALTER)\s+USER\b|\bREVOKE\s+ALL\b/i,
     "alterar usuario/permissao de banco pode trancar a aplicacao fora do proprio banco."],
  ];

  for (const [re, porque] of REGRAS) {
    if (re.test(cmd)) {
      process.stdout.write(JSON.stringify({
        hookSpecificOutput: {
          hookEventName: "PreToolUse",
          permissionDecision: "ask",
          permissionDecisionReason:
            "blindar-guard (risk-engine CRITICAL): " + porque +
            " Antes de aprovar: existe backup restaurado, e existe caminho de volta?"
        }
      }));
      return;
    }
  }
  process.stdout.write("{}");
});
' 2>/dev/null || liberar
