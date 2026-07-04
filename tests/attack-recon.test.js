#!/usr/bin/env node
// Testes do módulo 17 (blindar ataque — recon passivo externo).
// Roda o parser contra fixture e verifica classes de finding.
'use strict';

const assert = require('node:assert');
const { execFileSync } = require('node:child_process');
const { readFileSync, mkdtempSync, existsSync, mkdirSync, writeFileSync } = require('node:fs');
const { tmpdir } = require('node:os');
const { join, dirname } = require('node:path');
const { parseHeaders } = require('../scripts/attack-recon-report.js');

const root = dirname(__dirname);
let pass = 0, fail = 0;
function check(n, fn) { try { fn(); console.log(`  ok  - ${n}`); pass++; } catch (e) { console.error(`  FAIL - ${n}: ${e.message}`); fail++; } }

// ── parseHeaders ─────────────────────────────────────────────────────────────
check('parseHeaders extrai status HTTP/2', () => {
  const { status } = parseHeaders('HTTP/2 200\ncontent-type: text/plain\n');
  assert.equal(status, 200);
});
check('parseHeaders extrai status HTTP/1.1', () => {
  const { status } = parseHeaders('HTTP/1.1 404 Not Found\n\n');
  assert.equal(status, 404);
});
check('parseHeaders lowercase nomes', () => {
  const { headers } = parseHeaders('HTTP/2 200\nContent-Security-Policy: default-src\n');
  assert.equal(headers['content-security-policy'], 'default-src');
});

// ── report end-to-end ────────────────────────────────────────────────────────
const fixtureDir = join(root, 'tests', 'fixtures', 'attack-recon-tmp');
const outDir = mkdtempSync(join(tmpdir(), 'attack-recon-'));
const outRel = 'tests/tmp-attack-test.json'; // relativo pra evitar tradução MSYS
execFileSync('node', [join(root, 'scripts', 'attack-recon-report.js'),
  '--dir', 'tests/fixtures/attack-recon-tmp', '--url', 'https://exemplo.com', '--out', outRel
], { cwd: root, stdio: 'pipe' });

const doc = JSON.parse(readFileSync(join(root, outRel), 'utf8'));
require('node:fs').unlinkSync(join(root, outRel));

check('recon detecta >= 14 findings na fixture', () => assert.ok(doc.findings.length >= 14, `got ${doc.findings.length}`));
check('detecta .env exposto como CRIT', () => {
  const env = doc.findings.find(f => f.title.includes('.env'));
  assert.ok(env, '.env não achado');
  assert.equal(env.sev, 'crit');
  assert.equal(env.suggested_fix_category, 'runtime-secrets');
});
check('detecta debug endpoint /actuator como HIGH', () => {
  const dbg = doc.findings.find(f => f.title.toLowerCase().includes('actuator') || f.title.toLowerCase().includes('debug'));
  assert.ok(dbg, 'debug endpoint não achado');
  assert.equal(dbg.sev, 'high');
});
check('detecta CSP + HSTS ausentes como HIGH', () => {
  const csp = doc.findings.find(f => f.title.includes('CSP'));
  const hsts = doc.findings.find(f => f.title.includes('HSTS'));
  assert.equal(csp?.sev, 'high'); assert.equal(hsts?.sev, 'high');
});
check('detecta Cookie sem HttpOnly + Secure como HIGH', () => {
  assert.ok(doc.findings.find(f => f.title.includes('HttpOnly') && f.sev === 'high'));
  assert.ok(doc.findings.find(f => f.title.includes('Secure') && f.sev === 'high'));
});
check('detecta CORS * + credentials como HIGH', () => {
  const cors = doc.findings.find(f => f.title.includes('CORS'));
  assert.ok(cors); assert.equal(cors.sev, 'high');
});
check('detecta info leak Server + X-Powered-By como LOW', () => {
  const leaks = doc.findings.filter(f => f.title.includes('Info leak'));
  assert.equal(leaks.length, 2);
  assert.ok(leaks.every(l => l.sev === 'low'));
});
check('output valida contra findings.schema.json (campos obrigatórios)', () => {
  for (const f of doc.findings) {
    assert.ok(f.title && f.lens && f.sev && f.description, `campo faltando em ${JSON.stringify(f)}`);
    assert.ok(['crit', 'high', 'med', 'low'].includes(f.sev));
  }
});

console.log(`\n${pass} ok, ${fail} fail`);
process.exit(fail > 0 ? 1 : 0);
