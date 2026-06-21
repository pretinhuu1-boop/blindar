#!/usr/bin/env node
/**
 * blindar validate-schemas
 * ----------------------------------------------------------------------------
 * Valida outputs JSON do blindar (`check-*.json`, `run-report.json`,
 * `intelligence.yml`/`.json`) contra os schemas declarados em
 * `<skill>/schemas/*.schema.json`.
 *
 * Estratégia:
 *  1. Detecta o tipo do arquivo lendo o campo top-level `"schema"`.
 *  2. Mapeia esse identificador pra um schema concreto.
 *  3. Valida usando AJV se disponível (tenta `require('ajv')` local ou global).
 *     Se AJV NÃO estiver disponível, faz validação manual minimalista
 *     (required fields, tipos primitivos, enums, const). Suficiente pra
 *     detectar bumps silenciosos e drift estrutural.
 *
 * CLI:
 *   node scripts/validate-schemas.js --input .blindar/results/
 *   node scripts/validate-schemas.js --input .blindar/run-report.json
 *   node scripts/validate-schemas.js --help
 *
 * Exit:
 *   0 — todos os arquivos validados ok (ou nenhum arquivo encontrado)
 *   1 — algum arquivo com schema inválido
 *   2 — erro de uso (input inexistente, schema desconhecido, etc)
 *
 * Zero deps: usa só `node:fs`, `node:path`, `node:util.parseArgs`.
 */

'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { parseArgs } = require('node:util');

// ─── Localiza skill dir ─────────────────────────────────────────────────────
const SCRIPT_DIR = __dirname;
const SKILL_DIR = path.resolve(SCRIPT_DIR, '..');
const SCHEMAS_DIR = path.join(SKILL_DIR, 'schemas');

// Mapeia identificador "schema" → arquivo do schema
const SCHEMA_MAP = {
  'blindar/check-result@v1': 'check-result.schema.json',
  'blindar/run-report@v1':   'run-report.schema.json',
  'blindar/intelligence@v1': 'intelligence.schema.json',
};

// ─── CLI ─────────────────────────────────────────────────────────────────────
function printHelp() {
  process.stdout.write(`
blindar validate-schemas

Valida outputs JSON do blindar contra os JSON Schemas oficiais.

Usage:
  node scripts/validate-schemas.js --input <FILE|DIR>
  node scripts/validate-schemas.js --help

Options:
  --input <path>   Arquivo .json ou diretório a percorrer (não-recursivo).
                   Default: .blindar/results no cwd, se existir.
  --schemas <dir>  Override do diretório de schemas. Default: <skill>/schemas.
  --quiet          Só imprime erros (não lista arquivos válidos).
  --help           Esta ajuda.

Detecção de schema:
  O validador lê o campo top-level "schema" no JSON e mapeia pra um dos:
    ${Object.keys(SCHEMA_MAP).join('\n    ')}

Exit:
  0   tudo válido (ou nenhum arquivo)
  1   ao menos 1 arquivo inválido
  2   erro de uso
`);
}

let args;
try {
  args = parseArgs({
    options: {
      input:   { type: 'string' },
      schemas: { type: 'string' },
      quiet:   { type: 'boolean', default: false },
      help:    { type: 'boolean', short: 'h', default: false },
    },
    allowPositionals: false,
    strict: true,
  }).values;
} catch (e) {
  process.stderr.write(`ERRO: ${e.message}\n`);
  printHelp();
  process.exit(2);
}

if (args.help) { printHelp(); process.exit(0); }

const schemasDir = args.schemas || SCHEMAS_DIR;
const cwd = process.cwd();

let inputPath = args.input;
if (!inputPath) {
  const def = path.join(cwd, '.blindar', 'results');
  if (fs.existsSync(def)) { inputPath = def; }
  else {
    process.stderr.write(
      'ERRO: --input requerido (ou rode num projeto com .blindar/results/)\n'
    );
    process.exit(2);
  }
}

inputPath = path.resolve(cwd, inputPath);
if (!fs.existsSync(inputPath)) {
  process.stderr.write(`ERRO: --input não existe: ${inputPath}\n`);
  process.exit(2);
}

// ─── Carrega schemas ────────────────────────────────────────────────────────
const schemas = {};
for (const [id, file] of Object.entries(SCHEMA_MAP)) {
  const p = path.join(schemasDir, file);
  if (!fs.existsSync(p)) {
    process.stderr.write(`AVISO: schema ausente, será pulado: ${p}\n`);
    continue;
  }
  try {
    schemas[id] = { path: p, json: JSON.parse(fs.readFileSync(p, 'utf8')) };
  } catch (e) {
    process.stderr.write(`ERRO ao ler schema ${p}: ${e.message}\n`);
    process.exit(2);
  }
}

// ─── AJV opcional ────────────────────────────────────────────────────────────
let ajv = null;
function tryLoadAjv() {
  // Tenta resolver `ajv` (local ao projeto-alvo OU global).
  const candidates = [
    () => require('ajv/dist/2020.js'),
    () => require('ajv'),
  ];
  for (const fn of candidates) {
    try {
      const mod = fn();
      const Ajv = mod.default || mod.Ajv2020 || mod;
      const inst = new Ajv({ strict: false, allErrors: true });
      // addFormat best-effort (não exigimos ajv-formats)
      try {
        const af = require('ajv-formats');
        af(inst);
      } catch { /* ok sem formats */ }
      return inst;
    } catch { /* tenta próximo */ }
  }
  return null;
}
ajv = tryLoadAjv();

// ─── Validação manual (fallback sem AJV) ─────────────────────────────────────
function manualValidate(schema, data, prefix = '') {
  const errors = [];

  if (schema.type) {
    const types = Array.isArray(schema.type) ? schema.type : [schema.type];
    const actual =
      data === null ? 'null' :
      Array.isArray(data) ? 'array' :
      Number.isInteger(data) ? 'integer' :
      typeof data;
    // 'number' aceita integer
    const ok = types.some(t =>
      t === actual ||
      (t === 'number' && actual === 'integer') ||
      (t === 'integer' && actual === 'number' && Number.isInteger(data))
    );
    if (!ok) {
      errors.push(`${prefix || '<root>'}: esperado ${types.join('|')}, obteve ${actual}`);
      return errors; // não continua se tipo base errado
    }
  }

  if (schema.const !== undefined && data !== schema.const) {
    errors.push(`${prefix}: esperado const "${schema.const}", obteve "${data}"`);
  }

  if (schema.enum && !schema.enum.includes(data)) {
    errors.push(`${prefix}: valor "${data}" não está em [${schema.enum.join(', ')}]`);
  }

  if (typeof data === 'number') {
    if (schema.minimum !== undefined && data < schema.minimum) {
      errors.push(`${prefix}: ${data} < minimum ${schema.minimum}`);
    }
    if (schema.maximum !== undefined && data > schema.maximum) {
      errors.push(`${prefix}: ${data} > maximum ${schema.maximum}`);
    }
  }

  if (schema.type === 'object' || (schema.properties && typeof data === 'object' && !Array.isArray(data))) {
    if (Array.isArray(schema.required)) {
      for (const r of schema.required) {
        if (!(r in (data || {}))) {
          errors.push(`${prefix || '<root>'}: campo obrigatório ausente: "${r}"`);
        }
      }
    }
    if (schema.properties && data && typeof data === 'object') {
      for (const [k, subschema] of Object.entries(schema.properties)) {
        if (k in data) {
          errors.push(...manualValidate(subschema, data[k], prefix ? `${prefix}.${k}` : k));
        }
      }
    }
  }

  if (schema.type === 'array' && Array.isArray(data) && schema.items) {
    data.forEach((item, i) => {
      errors.push(...manualValidate(schema.items, item, `${prefix}[${i}]`));
    });
  }

  // anyOf — passa se ao menos um schema bater
  if (Array.isArray(schema.anyOf)) {
    const allErrs = schema.anyOf.map(s => manualValidate(s, data, prefix));
    if (!allErrs.some(e => e.length === 0)) {
      errors.push(`${prefix}: não satisfaz nenhum de anyOf (${allErrs.length} variantes)`);
    }
  }

  return errors;
}

function validateOne(file) {
  let raw, data;
  try {
    raw = fs.readFileSync(file, 'utf8');
    data = JSON.parse(raw);
  } catch (e) {
    return { file, ok: false, errors: [`JSON inválido: ${e.message}`] };
  }

  const schemaId = data && data.schema;
  if (!schemaId) {
    return { file, ok: false, errors: ['campo top-level "schema" ausente'] };
  }
  const entry = schemas[schemaId];
  if (!entry) {
    return { file, ok: false, errors: [`schema desconhecido: "${schemaId}"`] };
  }

  let errors;
  if (ajv) {
    const validate = ajv.compile(entry.json);
    const ok = validate(data);
    errors = ok ? [] : (validate.errors || []).map(e =>
      `${e.instancePath || '<root>'} ${e.message}${e.params ? ' ' + JSON.stringify(e.params) : ''}`
    );
  } else {
    errors = manualValidate(entry.json, data);
  }

  return { file, ok: errors.length === 0, errors, schemaId };
}

// ─── Coleta arquivos ─────────────────────────────────────────────────────────
function collectFiles(p) {
  const st = fs.statSync(p);
  if (st.isFile()) return [p];
  if (st.isDirectory()) {
    return fs.readdirSync(p)
      .filter(f => f.endsWith('.json'))
      .map(f => path.join(p, f))
      .filter(f => {
        try { return fs.statSync(f).isFile(); } catch { return false; }
      });
  }
  return [];
}

const files = collectFiles(inputPath);
if (files.length === 0) {
  process.stdout.write(`Nenhum .json encontrado em ${inputPath}\n`);
  process.exit(0);
}

// ─── Roda ────────────────────────────────────────────────────────────────────
const results = files.map(validateOne);
const invalid = results.filter(r => !r.ok);
const validCount = results.length - invalid.length;

if (!args.quiet) {
  process.stdout.write(`Validator: ${ajv ? 'AJV' : 'manual (zero-deps)'}\n`);
  process.stdout.write(`Inspecionados: ${results.length} arquivo(s)\n`);
}

for (const r of invalid) {
  process.stdout.write(`\n✗ ${path.relative(cwd, r.file)}\n`);
  for (const err of r.errors) {
    process.stdout.write(`    - ${err}\n`);
  }
}

process.stdout.write(`\n`);
if (invalid.length === 0) {
  process.stdout.write(`✓ Schemas válidos (${validCount}/${results.length})\n`);
  process.exit(0);
} else {
  process.stdout.write(
    `⚠ ${invalid.length} arquivo(s) com schema inválido (${validCount} ok)\n`
  );
  process.exit(1);
}
