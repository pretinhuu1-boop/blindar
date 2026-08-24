#!/usr/bin/env node
// Contrato do ingest do Sentinela: SARIF 2.1.0 → check-result do blindar.
import { sarifToResult } from '../scripts/sentinela-ingest.mjs';

let ok = 0, fail = 0;
const eq = (n, g, w) => { if (g === w) { console.log(`  ok  - ${n}`); ok++; } else { console.log(`  FAIL- ${n}: got ${JSON.stringify(g)} want ${JSON.stringify(w)}`); fail++; } };
const truthy = (n, v) => { if (v) { console.log(`  ok  - ${n}`); ok++; } else { console.log(`  FAIL- ${n}`); fail++; } };

const SARIF = {
  version: '2.1.0',
  runs: [{
    tool: { driver: { name: 'Sentinela' } },
    results: [
      { ruleId: 'missing-hsts', level: 'error', message: { text: 'Sem Strict-Transport-Security' },
        locations: [{ physicalLocation: { artifactLocation: { uri: 'https://app/' }, region: { startLine: 1 } } }] },
      { ruleId: 'token-in-localstorage', level: 'error', properties: { severity: 'crit' },
        message: { text: 'JWT em localStorage (lido em runtime)' } },
      { ruleId: 'verbose-cookie', level: 'warning', message: { text: 'Cookie sem SameSite' } },
      { ruleId: 'info', level: 'note', message: { text: 'nota informativa' } },
    ],
  }],
};

const res = sarifToResult(SARIF);
eq('schema correto', res.schema, 'blindar/check-result@v1');
eq('agent', res.agent, 'sentinela');
eq('4 findings', res.findings.length, 4);
eq('error → high', res.findings[0].severity, 'high');
eq('properties.severity crit preservado', res.findings[1].severity, 'crit');
eq('warning → med', res.findings[2].severity, 'med');
eq('note → low', res.findings[3].severity, 'low');
eq('tem crit/high → status failed', res.status, 'failed');
eq('exit_code 1 quando bloqueia', res.exit_code, 1);
truthy('ruleId embutido na mensagem', res.findings[0].message.includes('[missing-hsts]'));
truthy('file/line do location', res.findings[0].file === 'https://app/' && res.findings[0].line === '1');

// SARIF só com note → não bloqueia
const soNota = sarifToResult({ runs: [{ results: [{ ruleId: 'x', level: 'note', message: { text: 'y' } }] }] });
eq('só note → passed', soNota.status, 'passed');
eq('só note → exit 0', soNota.exit_code, 0);

// SARIF vazio → passed, sem findings
const vazio = sarifToResult({ runs: [] });
eq('vazio → passed', vazio.status, 'passed');
eq('vazio → 0 findings', vazio.findings.length, 0);

console.log(`\n${ok} ok, ${fail} fail`);
process.exit(fail ? 1 : 0);
