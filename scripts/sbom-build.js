#!/usr/bin/env node
/**
 * blindar SBOM builder (ROADMAP #17)
 * ============================================================
 * Constrói/valida `.blindar/sbom.json` — Bill of Materials de defesas.
 * Cada ATK fechado vira entry com id determinístico + proveniência
 * (PR/commit/agente/versão). Append-only, consumido pelo evidence-package.
 *
 * Zero deps. CommonJS. Reusa o ID determinístico de reproducibility.js.
 *
 * USO:
 *   node scripts/sbom-build.js --build findings.json --out .blindar/sbom.json
 *   node scripts/sbom-build.js --validate .blindar/sbom.json
 */
'use strict';

const { readFileSync, writeFileSync } = require('node:fs');
const { parseArgs } = require('node:util');
const { atkId } = require('./reproducibility.js');

const SEV_NORM = { crit: 'crit', critical: 'crit', high: 'high', med: 'med', medium: 'med', low: 'low', info: 'low' };

/** Constrói SBOM a partir de findings cobertos. meta = {blindar_version, generated_at}. */
function buildSbom(findings, meta = {}) {
  const seen = new Set();
  const atks = [];
  for (const f of findings || []) {
    const id = f.id && /^ATK-/.test(f.id) ? f.id : atkId(f);
    if (seen.has(id)) continue;
    seen.add(id);
    const cov = f.covered_by || {};
    atks.push({
      id,
      title: f.title || '',
      category: f.category || f.suggested_fix_category || f.lens || 'security',
      severity: SEV_NORM[(f.sev || f.severity || 'med')] || 'med',
      covered_at: f.covered_at || meta.generated_at || '',
      covered_by: {
        pr: cov.pr ?? null,
        commit: cov.commit ?? null,
        agent: cov.agent || f.agent || f.suggested_fix_category || 'unknown',
        blindar_version: cov.blindar_version || meta.blindar_version || '',
        round_n: cov.round_n ?? null,
      },
      tests_added: f.tests_added || [],
      guards_added: f.guards_added || [],
      frameworks: f.frameworks || [],
      verified_by_adversarial: !!f.verified_by_adversarial,
      adversarial_round_n: f.adversarial_round_n ?? null,
      regressed_at: f.regressed_at ?? null,
      accepted_risk: !!f.accepted_risk,
    });
  }
  // ordenação canônica: severity DESC depois id ASC (reproduzível)
  const rank = { crit: 0, high: 1, med: 2, low: 3 };
  atks.sort((a, b) => (rank[a.severity] - rank[b.severity]) || a.id.localeCompare(b.id));
  return { version: 1, generated_at: meta.generated_at || '', blindar_version: meta.blindar_version || '', atks };
}

/** Validação mínima (sem deps de schema lib): campos obrigatórios + tipos. */
function validateSbom(sbom) {
  const errors = [];
  if (typeof sbom !== 'object' || sbom === null) return ['SBOM não é objeto'];
  if (typeof sbom.version !== 'number') errors.push('version ausente/não-numérico');
  if (!Array.isArray(sbom.atks)) { errors.push('atks ausente/não-array'); return errors; }
  const ids = new Set();
  sbom.atks.forEach((a, i) => {
    if (!a.id || !/^ATK-/.test(a.id)) errors.push(`atks[${i}].id inválido`);
    if (ids.has(a.id)) errors.push(`atks[${i}].id duplicado: ${a.id}`);
    ids.add(a.id);
    if (!a.category) errors.push(`atks[${i}].category ausente`);
    if (!['crit', 'high', 'med', 'low'].includes(a.severity)) errors.push(`atks[${i}].severity inválido: ${a.severity}`);
  });
  return errors;
}

function main(argv) {
  const { values } = parseArgs({
    args: argv,
    options: {
      build: { type: 'string' }, out: { type: 'string' }, validate: { type: 'string' },
      version: { type: 'string' }, help: { type: 'boolean' },
    },
  });
  if (values.help || (!values.build && !values.validate)) {
    console.log('uso: sbom-build.js --build findings.json --out sbom.json | --validate sbom.json');
    return 0;
  }
  if (values.validate) {
    const sbom = JSON.parse(readFileSync(values.validate, 'utf8'));
    const errors = validateSbom(sbom);
    if (errors.length) { errors.forEach((e) => console.error(`  ✗ ${e}`)); return 1; }
    console.log(`✓ SBOM válido — ${sbom.atks.length} ATK(s)`);
    return 0;
  }
  const findings = JSON.parse(readFileSync(values.build, 'utf8')).findings || [];
  const sbom = buildSbom(findings, { blindar_version: values.version || '' });
  const out = values.out || '.blindar/sbom.json';
  writeFileSync(out, JSON.stringify(sbom, null, 2));
  console.log(`[sbom] ${sbom.atks.length} ATK(s) → ${out}`);
  return 0;
}

module.exports = { buildSbom, validateSbom };

if (require.main === module) process.exit(main(process.argv.slice(2)));
