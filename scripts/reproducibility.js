#!/usr/bin/env node
/**
 * blindar reproducibility (ROADMAP #16)
 * ============================================================
 * Determinismo parcial: mesmo projeto rodado 2x → mesmo hash canônico.
 *
 * Implementa a spec docs/specs/reproducibility.md:
 *   1. ID determinístico de ATK = "ATK-" + sha256(cat|file|line|vector)[:8]
 *   2. Ordenação canônica (id ASC, severity DESC, file path)
 *   3. Hash canônico que IGNORA campos voláteis (timestamps, PR#, commit)
 *
 * Zero deps (node:crypto, node:fs, node:util). CommonJS — alinhado ao
 * sarif-converter.js.
 *
 * USO:
 *   node scripts/reproducibility.js --check fileA.json fileB.json   # compara 2 runs
 *   node scripts/reproducibility.js --hash file.json                # imprime hash canônico
 */
'use strict';

const { createHash } = require('node:crypto');
const { readFileSync } = require('node:fs');
const { parseArgs } = require('node:util');

// Campos voláteis que NÃO entram no hash (variam entre runs legitimamente).
const VOLATILE = new Set([
  'last_updated', 'covered_at', 'updated_at', 'created_at', 'timestamp',
  'pr', 'pr_number', 'commit', 'commit_sha', 'sha', 'run_id', 'duration_ms',
]);

const SEV_RANK = { crit: 0, high: 1, med: 2, medium: 2, low: 3, info: 4 };

/** ID determinístico e estável de um ATK/finding. */
function atkId(finding) {
  const cat = finding.category || finding.suggested_fix_category || finding.lens || 'security';
  const file = finding.file || '';
  const line = finding.line_range || finding.line || '';
  const vector = finding.vector_signature || finding.title || finding.description || '';
  const sig = `${cat}|${file}|${line}|${vector}`;
  return 'ATK-' + createHash('sha256').update(sig).digest('hex').slice(0, 8);
}

/** Remove campos voláteis recursivamente e ordena chaves → objeto canônico. */
function canonicalize(value) {
  if (Array.isArray(value)) {
    const mapped = value.map(canonicalize);
    // ordena arrays de objetos por chave canônica estável
    mapped.sort((a, b) => stableKey(a).localeCompare(stableKey(b)));
    return mapped;
  }
  if (value && typeof value === 'object') {
    const out = {};
    for (const k of Object.keys(value).sort()) {
      if (VOLATILE.has(k)) continue;
      out[k] = canonicalize(value[k]);
    }
    return out;
  }
  return value;
}

function stableKey(v) {
  if (v && typeof v === 'object') {
    if (v.id) return String(v.id);
    const sev = SEV_RANK[v.sev || v.severity] ?? 9;
    return `${sev}|${v.file || ''}|${v.title || JSON.stringify(v)}`;
  }
  return String(v);
}

/** Hash canônico determinístico de um objeto (ignora voláteis + ordem). */
function canonicalHash(obj) {
  return createHash('sha256').update(JSON.stringify(canonicalize(obj))).digest('hex');
}

function main(argv) {
  const { values, positionals } = parseArgs({
    args: argv, options: { check: { type: 'boolean' }, hash: { type: 'boolean' }, help: { type: 'boolean' } },
    allowPositionals: true,
  });
  if (values.help || (!values.check && !values.hash)) {
    console.log('uso: reproducibility.js --hash f.json | --check a.json b.json');
    return 0;
  }
  if (values.hash) {
    const h = canonicalHash(JSON.parse(readFileSync(positionals[0], 'utf8')));
    console.log(h);
    return 0;
  }
  // --check
  const [a, b] = positionals;
  const ha = canonicalHash(JSON.parse(readFileSync(a, 'utf8')));
  const hb = canonicalHash(JSON.parse(readFileSync(b, 'utf8')));
  if (ha === hb) { console.log(`✓ reproduzível — hash idêntico: ${ha.slice(0, 16)}…`); return 0; }
  console.error(`✗ NÃO reproduzível:\n  ${a}: ${ha.slice(0, 16)}…\n  ${b}: ${hb.slice(0, 16)}…`);
  return 1;
}

module.exports = { atkId, canonicalize, canonicalHash };

if (require.main === module) process.exit(main(process.argv.slice(2)));
