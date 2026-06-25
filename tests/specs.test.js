#!/usr/bin/env node
/**
 * Testes dos specs implementados em v0.43 (ROADMAP #4, #16, #17).
 * Roda: node tests/specs.test.js
 */
'use strict';

const assert = require('node:assert');
const { atkId, canonicalHash } = require('../scripts/reproducibility.js');
const { buildSbom, validateSbom } = require('../scripts/sbom-build.js');
const { fuzzInMemory, tick } = require('../scripts/race-fuzz.js');

let pass = 0, fail = 0;
function check(name, fn) {
  try { fn(); console.log(`  ok  - ${name}`); pass++; }
  catch (e) { console.error(`  FAIL - ${name}: ${e.message}`); fail++; }
}
async function checkAsync(name, fn) {
  try { await fn(); console.log(`  ok  - ${name}`); pass++; }
  catch (e) { console.error(`  FAIL - ${name}: ${e.message}`); fail++; }
}

// ── #16 reproducibility ─────────────────────────────────────────────────────
check('atkId é estável pro mesmo finding', () => {
  const f = { category: 'database', file: 'a.js', line: 14, title: 'SQLi' };
  assert.equal(atkId(f), atkId({ ...f }));
});
check('atkId difere entre bugs diferentes', () => {
  assert.notEqual(atkId({ category: 'a', file: 'x' }), atkId({ category: 'b', file: 'y' }));
});
check('canonicalHash ignora campos voláteis (timestamp/PR/commit)', () => {
  const a = { findings: [{ id: 'ATK-1', sev: 'crit', last_updated: '2026-01-01', pr: 1, commit: 'aaa' }] };
  const b = { findings: [{ id: 'ATK-1', sev: 'crit', last_updated: '2026-12-31', pr: 99, commit: 'zzz' }] };
  assert.equal(canonicalHash(a), canonicalHash(b));
});
check('canonicalHash ignora ordem de array', () => {
  const a = { findings: [{ id: 'ATK-1', sev: 'high' }, { id: 'ATK-2', sev: 'crit' }] };
  const b = { findings: [{ id: 'ATK-2', sev: 'crit' }, { id: 'ATK-1', sev: 'high' }] };
  assert.equal(canonicalHash(a), canonicalHash(b));
});
check('canonicalHash MUDA se conteúdo real muda', () => {
  const a = { findings: [{ id: 'ATK-1', sev: 'crit' }] };
  const b = { findings: [{ id: 'ATK-1', sev: 'low' }] };
  assert.notEqual(canonicalHash(a), canonicalHash(b));
});

// ── #17 SBOM ────────────────────────────────────────────────────────────────
check('buildSbom gera entries válidas e determinísticas', () => {
  const findings = [
    { title: 'SQLi', category: 'database', sev: 'crit', file: 'a.js', line: 1, covered_by: { pr: 10, agent: 'db-architect', round_n: 3 } },
    { title: 'IDOR', category: 'access-control', sev: 'high', file: 'b.js', line: 2 },
  ];
  const sbom = buildSbom(findings, { blindar_version: '0.43.0' });
  assert.equal(sbom.atks.length, 2);
  assert.equal(sbom.atks[0].severity, 'crit'); // ordenado por sev
  assert.match(sbom.atks[0].id, /^ATK-/);
  assert.equal(sbom.atks[0].covered_by.agent, 'db-architect');
  assert.deepEqual(validateSbom(sbom), []); // sem erros
});
check('buildSbom dedup por id determinístico', () => {
  const f = { title: 'SQLi', category: 'database', sev: 'crit', file: 'a.js', line: 1 };
  const sbom = buildSbom([f, { ...f }], {});
  assert.equal(sbom.atks.length, 1);
});
check('validateSbom pega severity inválido e id ruim', () => {
  const errs = validateSbom({ version: 1, atks: [{ id: 'X-1', category: 'c', severity: 'wat' }] });
  assert.ok(errs.some((e) => e.includes('severity')));
  assert.ok(errs.some((e) => e.includes('id')));
});

// ── #4 race-fuzz ────────────────────────────────────────────────────────────
async function raceSuite() {
  await checkAsync('race-fuzz DETECTA check-then-act (oversell)', async () => {
    const res = await fuzzInMemory({
      setup: (N) => ({ stock: 5, N }),
      worker: async (s) => { const cur = s.stock; await tick(); if (cur > 0) s.stock = cur - 1; },
      invariant: (s, N) => s.stock === Math.max(0, 5 - N),
      levels: [20], rounds: 3,
    });
    assert.equal(res.violated, true);
  });
  await checkAsync('race-fuzz APROVA decremento atômico (reservation)', async () => {
    const res = await fuzzInMemory({
      setup: () => ({ stock: 5 }),
      worker: async (s) => { if (s.stock > 0) s.stock -= 1; },
      invariant: (s) => s.stock >= 0,
      levels: [10, 100], rounds: 3,
    });
    assert.equal(res.violated, false);
  });
}

(async () => {
  await raceSuite();
  console.log(`\n${pass} ok, ${fail} fail`);
  process.exit(fail > 0 ? 1 : 0);
})();
