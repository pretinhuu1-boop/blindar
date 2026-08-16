## SARIF converter (`scripts/sarif-converter.js`)

Zero deps Node 20+. Converte `.<NOME>/results/check-*.json` → SARIF 2.1.0 válido.

```javascript
#!/usr/bin/env node
// Converte results blindar-style → SARIF 2.1.0
// Uso: node sarif-converter.js [--input DIR] [--output FILE] [--help]

import { readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { parseArgs } from 'node:util';

const { values } = parseArgs({
  options: {
    input:  { type: 'string', default: '.<NOME>/results' },
    output: { type: 'string' },
    help:   { type: 'boolean', default: false },
  },
});

if (values.help) {
  console.log('Uso: sarif-converter.js [--input DIR] [--output FILE]');
  process.exit(0);
}

// Severity blindar → SARIF level
const sevMap = { crit: 'error', high: 'error', med: 'warning', low: 'note' };

const files = readdirSync(values.input)
  .filter(f => f.startsWith('check-') && f.endsWith('.json') && f !== 'aggregate.json');

const runs = files.map(f => {
  const content = JSON.parse(readFileSync(join(values.input, f), 'utf8'));
  const rules = [];
  const ruleIds = new Set();
  const results = (content.findings || []).map(finding => {
    const ruleId = `<NS>.${content.agent || f}.${finding.severity}`;
    if (!ruleIds.has(ruleId)) {
      ruleIds.add(ruleId);
      rules.push({ id: ruleId, shortDescription: { text: finding.severity } });
    }
    const result = {
      ruleId,
      level: sevMap[finding.severity] || 'none',
      message: { text: finding.message || '' },
    };
    if (finding.file) {
      result.locations = [{
        physicalLocation: {
          artifactLocation: { uri: finding.file },
          region: finding.line && /^\d+$/.test(String(finding.line))
            ? { startLine: parseInt(finding.line, 10) }
            : undefined,
        },
      }];
    }
    return result;
  });
  return {
    tool: { driver: { name: content.agent || f, rules } },
    results,
    invocations: [{ executionSuccessful: content.status === 'passed' }],
    versionControlProvenance: content.git_sha
      ? [{ revisionId: content.git_sha }]
      : undefined,
  };
});

const sarif = {
  $schema: 'https://docs.oasis-open.org/sarif/sarif/v2.1.0/schemas/sarif-schema-2.1.0.json',
  version: '2.1.0',
  runs,
};

const out = JSON.stringify(sarif, null, 2);
if (values.output) writeFileSync(values.output, out);
else process.stdout.write(out);
```

---

## Schema validator (`scripts/validate-schemas.js`)

Zero deps Node. AJV opcional, fallback manual.

```javascript
#!/usr/bin/env node
// Valida outputs blindar contra schemas/. AJV se disponível, fallback manual.
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, basename } from 'node:path';
import { fileURLToPath } from 'node:url';
import { dirname } from 'node:path';
import { parseArgs } from 'node:util';

const __dirname = dirname(fileURLToPath(import.meta.url));
const { values } = parseArgs({
  options: {
    input:   { type: 'string' },
    schemas: { type: 'string', default: join(__dirname, '..', 'schemas') },
    quiet:   { type: 'boolean', default: false },
    help:    { type: 'boolean', default: false },
  },
});

if (values.help || !values.input) {
  console.log('Uso: validate-schemas.js --input FILE|DIR [--schemas DIR] [--quiet]');
  process.exit(values.help ? 0 : 2);
}

// Carrega schemas
const schemaMap = {};
readdirSync(values.schemas).filter(f => f.endsWith('.json')).forEach(f => {
  const s = JSON.parse(readFileSync(join(values.schemas, f), 'utf8'));
  const constVal = s.properties?.schema?.const;
  if (constVal) schemaMap[constVal] = s;
});

// Tenta AJV; fallback manual
let validate;
try {
  const Ajv = (await import('ajv')).default;
  const ajv = new Ajv({ strict: false, allErrors: true });
  validate = (data, schema) => {
    const v = ajv.compile(schema);
    return v(data) ? [] : v.errors.map(e => `${e.instancePath} ${e.message}`);
  };
} catch {
  validate = (data, schema) => {
    const errors = [];
    // Validação manual básica (required, type, const, enum)
    const check = (obj, sch, path = '') => {
      if (sch.const !== undefined && obj !== sch.const) errors.push(`${path}: deve ser const ${sch.const}`);
      if (sch.required) for (const r of sch.required) if (!(r in obj)) errors.push(`${path}: faltando '${r}'`);
      if (sch.properties) for (const [k, v] of Object.entries(sch.properties)) {
        if (k in obj) check(obj[k], v, `${path}.${k}`);
      }
    };
    check(data, schema);
    return errors;
  };
}

// Lista arquivos
const stat = statSync(values.input);
const files = stat.isDirectory()
  ? readdirSync(values.input).filter(f => f.endsWith('.json')).map(f => join(values.input, f))
  : [values.input];

let total = 0, ok = 0;
for (const f of files) {
  total++;
  try {
    const data = JSON.parse(readFileSync(f, 'utf8'));
    const schema = schemaMap[data.schema];
    if (!schema) { if (!values.quiet) console.error(`⚠ ${basename(f)}: schema desconhecido (${data.schema})`); continue; }
    const errors = validate(data, schema);
    if (errors.length === 0) { ok++; if (!values.quiet) console.log(`✓ ${basename(f)}`); }
    else { if (!values.quiet) { console.error(`✗ ${basename(f)}:`); errors.forEach(e => console.error(`    ${e}`)); } }
  } catch (e) { if (!values.quiet) console.error(`✗ ${basename(f)}: ${e.message}`); }
}

if (!values.quiet) console.log(`\n${ok}/${total} válidos`);
process.exit(ok === total ? 0 : 1);
```

---

## Schemas obrigatórios (`schemas/*.json`)

`schemas/check-result.schema.json`:
```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://blindar.dev/schemas/check-result-v1.json",
  "type": "object",
  "required": ["schema", "agent", "status", "findings_count", "findings"],
  "properties": {
    "schema": { "const": "<NS>/check-result@v1" },
    "agent": { "type": "string" },
    "ran_at": { "type": "string", "format": "date-time" },
    "git_sha": { "type": "string" },
    "status": { "enum": ["passed", "failed", "skipped", "deferred", "errored"] },
    "exit_code": { "type": "integer" },
    "duration_sec": { "type": "integer", "minimum": 0 },
    "findings_count": { "type": "integer", "minimum": 0 },
    "findings": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["severity", "message"],
        "properties": {
          "severity": { "enum": ["crit", "high", "med", "low"] },
          "message": { "type": "string" },
          "file": { "type": "string" },
          "line": { "anyOf": [{ "type": "string" }, { "type": "integer" }] }
        }
      }
    }
  }
}
```

`schemas/run-report.schema.json`: análogo, valida campos do run-report.

---

## `scripts/<NOME>-fix.sh` — killer feature (LLM gera patch+teste+PR)

```bash
#!/usr/bin/env bash
# Pega finding do run-report → Claude API → patch+teste → branch+commit (opcional PR)
#
# Uso:
#   bash scripts/<NOME>-fix.sh --finding-id check-X:0 --dry-run
#   bash scripts/<NOME>-fix.sh --auto-all --apply --pr
#
# Flags:
#   --finding-id <agent>:<idx>  Qual finding fixar
#   --auto-all                  Itera crit/high do último run-report
#   --dry-run                   Mostra patch, NÃO aplica (default)
#   --apply                     Aplica patch + cria branch + commit
#   --branch <name>             Branch nome (default <NOME>-fix/<agent>-<ts>)
#   --pr                        Após --apply, abre PR via gh
#
# Garantias:
# - DEFAULT dry-run (--apply explícito)
# - Branch separada (recusa main/master/develop/production)
# - Valida com `git apply --check` antes de aplicar
# - Skip gracioso sem ANTHROPIC_API_KEY
```

Implementação: lê finding do `.<NOME>/results/check-<agent>.json`, monta prompt com 200 linhas ao redor do `file:line`, força tool_use com schema `{patch, test, explanation, confidence}`, valida git apply, cria branch separada, opcionalmente PR.

---

## CLI Node zero-deps (`cli/bin/<NOME>.js`)

```javascript
#!/usr/bin/env node
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { readFileSync } from 'node:fs';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const CLI_ROOT = join(__dirname, '..');
const SKILL_ROOT = join(CLI_ROOT, '..');

function parseArgs(argv) {
  const out = { _: [] };
  const flags = new Set(['help', 'h', 'version', 'v', 'fast', 'json', 'force', 'apply', 'strict', 'auto-all', 'pr', 'dry-run']);
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--help' || a === '-h') out.help = true;
    else if (a === '--version' || a === '-v') out.version = true;
    else if (a.startsWith('--')) {
      const [k, v] = a.slice(2).split('=');
      if (v !== undefined) out[k] = v;
      else if (flags.has(k)) out[k] = true;
      else if (i + 1 < argv.length && !argv[i+1].startsWith('-')) out[k] = argv[++i];
      else out[k] = true;
    } else if (a.startsWith('-')) out[a.slice(1)] = true;
    else out._.push(a);
  }
  return out;
}

const c = {
  red:    s => `\x1b[31m${s}\x1b[0m`,
  green:  s => `\x1b[32m${s}\x1b[0m`,
  yellow: s => `\x1b[33m${s}\x1b[0m`,
  blue:   s => `\x1b[34m${s}\x1b[0m`,
  bold:   s => `\x1b[1m${s}\x1b[0m`,
};

const args = parseArgs(process.argv.slice(2));
const cmd = args._[0] || 'help';

const COMMANDS = {
  check:   './commands/check.js',
  init:    './commands/init.js',
  fix:     './commands/fix.js',
  version: './commands/version.js',
  help:    './commands/help.js',
};

if (args.version) {
  const pkg = JSON.parse(readFileSync(join(CLI_ROOT, 'package.json'), 'utf8'));
  console.log(`<NOME> v${pkg.version}`);
  process.exit(0);
}

if (args.help || !COMMANDS[cmd]) {
  if (!COMMANDS[cmd] && cmd !== 'help') console.error(c.red(`Comando desconhecido: ${cmd}`));
  await import('../commands/help.js').then(m => m.default({ cliRoot: CLI_ROOT, skillRoot: SKILL_ROOT, c }));
  process.exit(args.help ? 0 : 1);
}

try {
  const mod = await import('../' + COMMANDS[cmd].replace('./', ''));
  const exitCode = await mod.default({ args, cliRoot: CLI_ROOT, skillRoot: SKILL_ROOT, c });
  process.exit(exitCode || 0);
} catch (err) {
  console.error(c.red(`Erro em '${cmd}': ${err.message}`));
  if (process.env.DEBUG) console.error(err.stack);
  process.exit(1);
}
```

`package.json` mínimo (sem dependencies):
```json
{
  "name": "<NOME>",
  "version": "0.1.0",
  "description": "<PROPÓSITO>",
  "type": "module",
  "bin": { "<NOME>": "./bin/<NOME>.js" },
  "engines": { "node": ">=20.0.0" }
}
```

---

