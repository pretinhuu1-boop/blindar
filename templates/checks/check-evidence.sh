#!/usr/bin/env bash
# Gate de evidência: todo achado que bloqueia precisa dizer ONDE.
#
# Origem: relatório que afirma "PostgreSQL está configurado" ou "autenticação
# segura" não é auditável — quem lê não tem como confirmar nem refutar, e quem
# precisa corrigir não sabe por onde começar. A regra de escrita ("cite arquivo,
# linha, comando") é fácil de esquecer; este gate a torna verificável na fonte,
# antes de virar prosa.
#
# Escopo deliberado: valida a ESTRUTURA do achado, não a qualidade do texto.
# Um grep não julga se uma frase é evidência; ele julga se há onde verificar.
#
# "Onde verificar" tem duas formas, e confundi-las gera falso positivo. Achado
# ESTÁTICO aponta arquivo e linha. Achado de RUNTIME não tem arquivo por
# natureza — "erro de 100% acima do SLO de 5% com 10 concorrentes" é evidência
# completa, e exigir um `file` dele reprovaria justamente o achado mais concreto
# do relatório. Para esses agentes a prova é a MEDIÇÃO, e o gate exige número na
# mensagem em vez de localização.
#
# Como o check-termination.sh e o check-release-gates.sh, este é um decisor —
# não chama emit_result e por isso fica fora do denominador de cobertura de
# fixtures (critério 2 do check-selftest.sh).
#
# Exit: 0 = toda evidência presente | 1 = achado bloqueante sem localização
#       | 5 = sem leitor de JSON (sem medição não há aprovação)

set -uo pipefail

BLINDAR_DIR="${BLINDAR_DIR:-.blindar}"
RESULTS_DIR="$BLINDAR_DIR/results"
GATES="$BLINDAR_DIR/gates.json"

command -v node >/dev/null 2>&1 || {
  echo "❌ 'node' ausente — impossível ler os results. Sem leitura não há" >&2
  echo "   veredito, e ausência de veredito nunca é aprovação." >&2
  exit 5
}

[ -d "$RESULTS_DIR" ] || {
  echo "❌ $RESULTS_DIR não existe. Rode os checks antes." >&2
  exit 1
}

echo "═══ blindar — gate de evidência ═══"
echo ""

node -e '
const fs = require("fs"), path = require("path");
const dir = process.argv[1], gatesPath = process.argv[2];

let names = [];
try { names = fs.readdirSync(dir); } catch { process.exit(1); }

// Agentes cuja prova é medição de runtime, não localização em arquivo.
const POR_MEDICAO = new Set([
  "check-load-test", "check-pentest", "check-pentest-active", "check-attack-recon",
  "check-smoke-runtime", "check-race-fuzzing", "check-lighthouse", "check-runtime-adversarial",
]);
// Número com unidade, faixa percentual, código de status ou tempo.
const TEM_MEDICAO = /\d/;

let semEvidencia = 0, total = 0;
const ofensores = [];

for (const name of names.filter(n => /^check-.*\.json$/.test(n))) {
  let j;
  try { j = JSON.parse(fs.readFileSync(path.join(dir, name), "utf8")); } catch { continue; }
  const findings = Array.isArray(j.findings) ? j.findings : [];
  const porMedicao = POR_MEDICAO.has(j.agent);
  for (const f of findings) {
    if (!f || !f.severity) continue;
    total++;
    const bloqueante = f.severity === "crit" || f.severity === "high";
    if (!bloqueante) continue;
    const temLocal = typeof f.file === "string" && f.file.trim() !== "";
    const temMedicao = porMedicao && TEM_MEDICAO.test(String(f.message || ""));
    if (!temLocal && !temMedicao) {
      semEvidencia++;
      const falta = porMedicao ? "sem medição na mensagem" : "sem arquivo";
      ofensores.push(`${j.agent}: [${f.severity}] (${falta}) ${String(f.message || "").slice(0, 80)}`);
    }
  }
}
const semLocal = semEvidencia;

console.log(`  achados analisados        : ${total}`);
console.log(`  crit/high sem evidência   : ${semLocal}`);

// Gates: cada dimensão precisa dizer POR QUE tem aquele status. Gate sem
// evidência é opinião, e o relatório final cita justamente esse campo.
let gatesSemEvidencia = [];
try {
  const g = JSON.parse(fs.readFileSync(gatesPath, "utf8"));
  gatesSemEvidencia = (g.gates || [])
    .filter(x => !x.evidence || String(x.evidence).trim() === "")
    .map(x => x.gate);
  console.log(`  gates sem evidência       : ${gatesSemEvidencia.length}`);
} catch {
  console.log("  gates.json                : ausente (rode check-release-gates.sh)");
}

if (ofensores.length) {
  console.log("");
  console.log("  Achados bloqueantes sem arquivo:");
  for (const o of ofensores.slice(0, 20)) console.log("    • " + o);
  if (ofensores.length > 20) console.log(`    … e mais ${ofensores.length - 20}`);
}
if (gatesSemEvidencia.length) {
  console.log("");
  console.log("  Gates sem evidência: " + gatesSemEvidencia.join(", "));
}

process.exit(semLocal > 0 || gatesSemEvidencia.length > 0 ? 1 : 0);
' "$RESULTS_DIR" "$GATES"
RC=$?

echo ""
if [ "$RC" -eq 0 ]; then
  echo "✅ toda afirmação bloqueante tem onde ser verificada"
else
  echo "❌ há afirmação bloqueante sem localização — não é acionável nem auditável"
  echo "   Todo finding crit/high precisa de 'file' preenchido; todo gate, de 'evidence'."
fi
exit $RC
