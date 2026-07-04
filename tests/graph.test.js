#!/usr/bin/env node
// Testa scripts/graph-build.js contra a fixture project-graph.
// Roda via tests/run-tests.sh. Exit 0 = ok.
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const SKILL = join(__dirname, '..');
const FIX = join(__dirname, 'fixtures', 'project-graph');
const SCHEMA = JSON.parse(readFileSync(join(SKILL, 'schemas', 'graph.schema.json'), 'utf8'));

let ok = 0, fail = 0;
const t = (name, cond) => { if (cond) { ok++; console.log('  ok  - ' + name); } else { fail++; console.log('  FAIL- ' + name); } };

const out = execFileSync('node', [join(SKILL, 'scripts', 'graph-build.js'), '--dir', FIX, '--json'], { encoding: 'utf8' });
const g = JSON.parse(out);

const eps = g.nodes.filter((n) => n.type === 'endpoint');
const ext = eps.filter((n) => !n.internal);
const int = eps.filter((n) => n.internal);

t('grafo declara schema blindar/graph@v1', g.schema === 'blindar/graph@v1');
t('detecta 3 endpoints (2 externos + 1 rpc interno)', eps.length === 3);
t('classifica 2 endpoints como externos', ext.length === 2);
t('classifica /rpc/ como interno (nao aceita chamada externa)', int.length === 1 && int[0].path.includes('/rpc/'));
t('detecta worker de fila (bullmq)', g.nodes.some((n) => n.type === 'worker'));
t('service api exposto (ports) = superficie externa', g.nodes.some((n) => n.type === 'service' && n.name === 'api' && n.exposed));
t('service db sem ports = interno', g.nodes.some((n) => n.type === 'service' && n.name === 'db' && !n.exposed));
t('depends_on api->db e api->redis', g.edges.filter((e) => e.type === 'depends_on' && e.from === 'svc:api').length >= 2);
t('pacote express detectado como no package', g.nodes.some((n) => n.type === 'package' && n.name === 'express'));

// validacao minima contra schema (required + const + enum de tipos)
function validate(data, schema, path = '') {
  const errs = [];
  if (schema.const !== undefined && data !== schema.const) errs.push(`${path}: != const`);
  if (schema.required) for (const r of schema.required) if (!(r in (data || {}))) errs.push(`${path}: falta '${r}'`);
  if (schema.properties && data && typeof data === 'object')
    for (const [k, v] of Object.entries(schema.properties)) if (k in data) errs.push(...validate(data[k], v, `${path}.${k}`));
  if (schema.type === 'array' && Array.isArray(data) && schema.items)
    data.forEach((it, i) => errs.push(...validate(it, schema.items, `${path}[${i}]`)));
  if (schema.enum && data !== undefined && !schema.enum.includes(data)) errs.push(`${path}: '${data}' fora do enum`);
  return errs;
}
const errs = validate(g, SCHEMA);
t('output valida contra graph.schema.json', errs.length === 0);
if (errs.length) errs.slice(0, 5).forEach((e) => console.log('     ' + e));

console.log(`\n${ok} ok, ${fail} fail`);
process.exit(fail === 0 ? 0 : 1);
