#!/usr/bin/env bash
# Materialização determinística do agente: runtime-secrets + supply-chain (parcial)
# Detecta secrets hardcoded usando gitleaks.
# Exit 0 se zero secrets. Exit 1 se achar.

BLINDAR_AGENT="check-secrets"
source "$(dirname "$0")/_lib.sh"

log_section "Check: secrets hardcoded (gitleaks)"

if ! command -v gitleaks >/dev/null 2>&1; then
  log_warn "gitleaks não instalado. Instale: brew install gitleaks  (ou: go install github.com/gitleaks/gitleaks/v8@latest)"
  BLINDAR_MISSING_TOOL="gitleaks"   # sem isto o result sai missing_tool:null
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

# A contagem de leaks sai do parse do JSON do gitleaks. Antes isso era jq, e
# `jq 'length' || echo 0` devolvia 0 sem jq: o gate de segredos reportava PASSED
# com segredos presentes (falha ABERTA). Virou require_tool jq, que ao menos não
# aprovava — mas trocou uma falha aberta por um buraco de cobertura: numa máquina
# com gitleaks e sem jq, o check de segredo simplesmente não rodava. Medido no
# teste de máquina limpa, e o doctor ainda dizia que sem jq não se perde nada.
#
# Agora o parse é em node, que já é dependência ESSENCIAL do blindar (sem ele o
# orquestrador nem resolve o MODULE-MAP). Uma dependência a menos para o check
# mais importante do conjunto.
require_tool node "parsing do relatório JSON do gitleaks"

# ─── FALSO NEGATIVO CRÍTICO que existia aqui ───
# Era: `if gitleaks protect --staged; then scope=staged; elif detect --no-git; …`
#
# O código de saída do gitleaks é 0 = NENHUM vazamento, 1 = ACHOU, >1 = erro.
# Numa auditoria normal não há nada staged: `protect --staged` varria o índice
# vazio, achava nada, saía 0 — e o `if` dava certo. O scan da árvore de trabalho
# no `elif` NUNCA rodava. Chave AWS real em src/ era reportada como `passed`.
#
# E quando `protect` ACHAVA algo saía 1, o `if` falhava, caía no `elif`, que ao
# achar também saía 1 — nenhum ramo pegava, `scope` ficava indefinido e sob
# `set -u` o log de falha abortava o script. Achar segredo quebrava o check.
#
# O check de segredo aprovando por ter varrido o lugar errado é a pior forma da
# falha que este projeto persegue: não é ruído, é silêncio no lugar do alarme.
#
# Agora: a árvore de trabalho é SEMPRE varrida (é o que uma auditoria quer), o
# índice é varrido A MAIS quando existe, e o veredito vem da CONTAGEM do
# relatório — nunca do código de saída.
#
# --redact: sem isso os VALORES dos segredos apareciam no stdout/log de CI via
# `tee /dev/stderr`. O check só lê RuleID/File/StartLine, então redigir não perde
# nada e evita vazar o segredo no próprio pipeline que o caça.
TMP=$(mktemp)
TMP_STAGED=$(mktemp)
scope="working-tree"

gitleaks detect --no-git --redact --report-format=json --report-path="$TMP" 2>&1 | tee /dev/stderr
GL_RC=${PIPESTATUS[0]}

if git diff --cached --quiet 2>/dev/null; then
  : # índice vazio: nada a mais para varrer
else
  gitleaks protect --staged --redact --report-format=json --report-path="$TMP_STAGED" 2>&1 | tee /dev/stderr
  GL_RC_S=${PIPESTATUS[0]}
  [ "${GL_RC_S:-0}" -gt 1 ] && GL_RC="$GL_RC_S"
  scope="working-tree+staged"
  # Une os dois relatórios num só, deduplicando por regra+arquivo+linha.
  node -e '
    const fs = require("fs");
    const ler = (p) => { try { const j = JSON.parse(fs.readFileSync(p, "utf8") || "[]");
                               return Array.isArray(j) ? j : []; } catch (e) { return []; } };
    const vistos = new Set(), saida = [];
    for (const l of [...ler(process.argv[1]), ...ler(process.argv[2])]) {
      const k = [l.RuleID, l.File, l.StartLine].join("::");
      if (vistos.has(k)) continue;
      vistos.add(k); saida.push(l);
    }
    fs.writeFileSync(process.argv[1], JSON.stringify(saida));
  ' "$TMP" "$TMP_STAGED" 2>/dev/null
fi
rm -f "$TMP_STAGED"

# >1 é erro do gitleaks (regex inválida, permissão, binário quebrado). Relatório
# vazio depois de erro não é "sem segredo", é scan que não terminou.
if [ "${GL_RC:-0}" -gt 1 ]; then
  log_fail "gitleaks terminou com erro (exit $GL_RC) — o scan não completou"
  log_warn "isto NÃO é 'nenhum segredo': é medição que não aconteceu."
  BLINDAR_MISSING_TOOL="gitleaks(exit $GL_RC)"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  rm -f "$TMP"
  exit 0
fi

# Erro de parse NÃO pode virar 0. Relatório ilegível é ausência de medição, e
# ausência de medição não é ausência de segredo — sai -1 e o bloco abaixo trata.
LEAK_COUNT=$(node -e '
  const fs = require("fs");
  try {
    const j = JSON.parse(fs.readFileSync(process.argv[1], "utf8") || "[]");
    process.stdout.write(String(Array.isArray(j) ? j.length : 0));
  } catch (e) { process.stdout.write("-1"); }
' "$TMP" 2>/dev/null || echo -1)

if [ "$LEAK_COUNT" = "-1" ]; then
  log_fail "relatório do gitleaks ilegível — o scan não pôde ser lido"
  log_warn "isto NÃO é 'nenhum segredo': é medição que não aconteceu."
  BLINDAR_MISSING_TOOL="gitleaks(saída inválida)"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  rm -f "$TMP"
  exit 0
fi

if [ "$LEAK_COUNT" -gt 0 ]; then
  log_fail "$LEAK_COUNT secret(s) detectado(s) (scope: $scope)"
  # `< <(...)` em vez de `jq | while`: num pipe o while roda em SUBSHELL e o array
  # FINDINGS (populado por add_finding) morre com ela → emit_result reportava
  # `failed` com findings:[] (achou segredo mas não listou nenhum).
  # TSV e não JSON por linha: já custou um bug nesta base parsear JSON com
  # ferramenta de texto quando a mensagem continha aspas. Aqui os campos são
  # RuleID/File/StartLine, nenhum deles com tab.
  while IFS=$'\t' read -r rule file line; do
    [ -z "$rule" ] && continue
    add_finding "crit" "Secret hardcoded: $rule" "$file" "$line"
  done < <(node -e '
    const fs = require("fs");
    let j; try { j = JSON.parse(fs.readFileSync(process.argv[1], "utf8") || "[]"); } catch (e) { j = []; }
    const limpa = (s) => String(s == null ? "" : s).replace(/[\t\r\n]/g, " ");
    // \n final obrigatório: `while read` do bash descarta a última linha sem ele.
    for (const l of j) process.stdout.write(
      [limpa(l.RuleID), limpa(l.File), limpa(l.StartLine)].join("\t") + "\n");
  ' "$TMP" 2>/dev/null)
  emit_result "$BLINDAR_AGENT" "failed" 1
  rm -f "$TMP"
  exit 1
fi

rm -f "$TMP"
emit_result "$BLINDAR_AGENT" "passed" 0
exit 0
