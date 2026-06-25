#!/usr/bin/env node
/**
 * blindar race-fuzz harness (ROADMAP #4)
 * ============================================================
 * Fuzz dirigido a races — testes ATIVOS de concorrência além do
 * adversarial review (que é só análise estática).
 *
 * Implementa docs/specs/race-fuzzing.md:
 *   - dispara N requests concorrentes ao mesmo recurso, N escalonando
 *   - verifica invariante (saldo consistente? constraint respeitado?)
 *   - se algum nível quebra → race real
 *
 * Dois modos:
 *   1. in-memory: testa um worker JS (unit, determinístico) — usado nos
 *      testes do próprio skill e pra validar reservation pattern.
 *   2. http: dispara contra um endpoint real (precisa app de pé).
 *
 * Zero deps (usa fetch nativo do Node 20+). CommonJS.
 *
 * USO (http):
 *   node scripts/race-fuzz.js --url http://localhost:3000/api/charge \
 *     --method POST --body '{"amount":10}' --levels 10,100,1000
 */
'use strict';

const { parseArgs } = require('node:util');

// LCG determinístico (sem Math.random — reproduzível por seed).
function shuffle(n, seed) {
  const idx = [...Array(n).keys()];
  let s = (seed >>> 0) || 1;
  for (let i = n - 1; i > 0; i--) {
    s = (1103515245 * s + 12345) & 0x7fffffff;
    const j = s % (i + 1);
    [idx[i], idx[j]] = [idx[j], idx[i]];
  }
  return idx;
}

const tick = () => new Promise((r) => setImmediate(r));

/**
 * Roda fuzz in-memory contra um worker que muta estado compartilhado.
 * @returns {Promise<{violated, firstViolationLevel, levels}>}
 */
async function fuzzInMemory({ setup, worker, invariant, levels = [10, 100, 1000], rounds = 5 }) {
  for (const N of levels) {
    for (let r = 0; r < rounds; r++) {
      const state = setup(N);
      const order = shuffle(N, r + 1);
      await Promise.all(order.map((i) => worker(state, i, N)));
      if (!invariant(state, N)) {
        return { violated: true, firstViolationLevel: N, levels };
      }
    }
  }
  return { violated: false, firstViolationLevel: null, levels };
}

/** Dispara N requests HTTP concorrentes; coleta status. Precisa app de pé. */
async function fuzzHttp({ url, method = 'POST', body = null, headers = {}, levels = [10, 100] }) {
  const results = [];
  for (const N of levels) {
    const reqs = Array.from({ length: N }, () =>
      fetch(url, { method, headers: { 'content-type': 'application/json', ...headers }, body })
        .then((r) => r.status)
        .catch(() => 0)
    );
    const statuses = await Promise.all(reqs);
    const ok = statuses.filter((s) => s >= 200 && s < 300).length;
    results.push({ level: N, ok, total: N, statuses_sample: statuses.slice(0, 5) });
  }
  return results;
}

async function main(argv) {
  const { values } = parseArgs({
    args: argv,
    options: {
      url: { type: 'string' }, method: { type: 'string' }, body: { type: 'string' },
      levels: { type: 'string' }, help: { type: 'boolean' },
    },
  });
  if (values.help || !values.url) {
    console.log('uso: race-fuzz.js --url <endpoint> [--method POST] [--body JSON] [--levels 10,100,1000]');
    console.log('(modo in-memory: importar fuzzInMemory como módulo)');
    return values.url ? 0 : 0;
  }
  const levels = (values.levels || '10,100').split(',').map(Number);
  const res = await fuzzHttp({ url: values.url, method: values.method, body: values.body, levels });
  console.log('[race-fuzz] resultado por nível:');
  for (const r of res) console.log(`  N=${r.total}: ${r.ok} OK (${(r.ok / r.total * 100).toFixed(0)}%)`);
  console.log('Interprete: se a taxa de OK NÃO cai quando deveria (ex: saques > saldo), há race.');
  return 0;
}

module.exports = { fuzzInMemory, fuzzHttp, tick };

if (require.main === module) main(process.argv.slice(2)).then((c) => process.exit(c));
