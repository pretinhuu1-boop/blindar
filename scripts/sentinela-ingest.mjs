#!/usr/bin/env node
// sentinela-ingest.mjs — converte o SARIF do Sentinela num check-result do blindar.
//
// O Sentinela audita a app RODANDO e LOGADA (browser real, passa 2FA/SSO) e
// prova em runtime o que o blindar infere do código. Esta ponte traz os achados
// dele para dentro do relatório do blindar: um result em .blindar/results/ que o
// gate lê, o report conta e o `reproduzir` sabe explicar.
//
// Uso:
//   node scripts/sentinela-ingest.mjs <arquivo.sarif> [--out .blindar/results/sentinela.json]
//   import { sarifToResult } from './sentinela-ingest.mjs'
//
// Zero dependências.

import fs from 'node:fs';
import path from 'node:path';

// SARIF level → severidade do blindar. `properties.severity` (não-padrão, mas o
// SARIF permite) tem prioridade porque preserva o "crit" que o level SARIF não
// distingue de "high".
const LEVEL_TO_SEV = { error: 'high', warning: 'med', note: 'low', none: 'low' };

function normSev(s) {
  const v = String(s || '').toLowerCase();
  if (v.startsWith('crit')) return 'crit';
  if (v === 'high') return 'high';
  if (v === 'med' || v === 'medium') return 'med';
  if (v === 'low' || v === 'info' || v === 'informational') return 'low';
  return null;
}

export function sarifToResult(sarif, { agent = 'sentinela' } = {}) {
  const findings = [];
  const runs = Array.isArray(sarif?.runs) ? sarif.runs : [];
  for (const run of runs) {
    for (const r of (Array.isArray(run.results) ? run.results : [])) {
      const sev = normSev(r.properties?.severity) || LEVEL_TO_SEV[r.level] || 'med';
      const loc = r.locations?.[0]?.physicalLocation;
      const file = loc?.artifactLocation?.uri || '';
      const line = loc?.region?.startLine || '';
      const text = (r.message?.text || r.ruleId || 'achado do Sentinela').slice(0, 2000);
      const rule = r.ruleId ? `[${r.ruleId}] ` : '';
      findings.push({ severity: sev, message: `${rule}${text}`, file: String(file), line: String(line) });
    }
  }
  const hasBlock = findings.some((f) => f.severity === 'crit' || f.severity === 'high');
  return {
    schema: 'blindar/check-result@v1',
    agent,
    status: hasBlock ? 'failed' : (findings.length ? 'passed' : 'passed'),
    exit_code: hasBlock ? 1 : 0,
    missing_tool: null,
    source: 'sentinela (DAST runtime, sessão autenticada)',
    findings,
  };
}

// CLI
if (process.argv[1] && process.argv[1].endsWith('sentinela-ingest.mjs')) {
  const args = process.argv.slice(2);
  const file = args.find((a) => !a.startsWith('--'));
  const outIdx = args.indexOf('--out');
  const out = outIdx >= 0 ? args[outIdx + 1] : '.blindar/results/sentinela.json';
  if (!file) { console.error('uso: node scripts/sentinela-ingest.mjs <arquivo.sarif> [--out path]'); process.exit(64); }
  let sarif;
  try { sarif = JSON.parse(fs.readFileSync(file, 'utf8')); }
  catch (e) { console.error(`SARIF ilegível (${file}): ${e.message} — isto não é "sem achado", é ingest que não aconteceu.`); process.exit(2); }
  const result = sarifToResult(sarif);
  fs.mkdirSync(path.dirname(out), { recursive: true });
  fs.writeFileSync(out, JSON.stringify(result, null, 2));
  console.log(`sentinela → ${out}: status=${result.status}, ${result.findings.length} finding(s) (${result.findings.filter((f) => f.severity === 'crit' || f.severity === 'high').length} crit/high).`);
  process.exit(result.exit_code);
}
