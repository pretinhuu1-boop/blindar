#!/usr/bin/env node
// blindar graph — grafo de conhecimento multi-modal do codebase (Graphify nativo).
// Constrói UMA vez na discovery e é reusado por todos os agentes → mais cobertura
// (call graph, data-flow, fronteira interno×externo) e MENOS tokens (não re-varre
// por agente). Zero dependências (Node 20+).
//
// Uso: node scripts/graph-build.js [--dir .] [--out .blindar/graph.json] [--json]
//
// Saída (.blindar/graph.json), valida contra schemas/graph.schema.json:
//   { schema, built_at, root, stats, nodes[], edges[], surface{external[],internal[]} }
//
// Tipos de nó: file | package | endpoint | service | env | model | worker
// Tipos de aresta: imports | exposes | depends_on | uses_env

import { readdirSync, readFileSync, writeFileSync, mkdirSync, statSync, existsSync } from 'node:fs';
import { join, relative, sep, basename } from 'node:path';
import { parseArgs } from 'node:util';

const { values } = parseArgs({
  options: {
    dir: { type: 'string', default: '.' },
    out: { type: 'string', default: join('.blindar', 'graph.json') },
    json: { type: 'boolean', default: false },
  },
});

const ROOT = values.dir;
const IGNORE_DIRS = new Set(['node_modules', '.git', 'dist', 'build', '.next', '.blindar', 'coverage', 'vendor', '__pycache__', '.venv', 'venv']);
const SRC_EXT = new Set(['.ts', '.tsx', '.js', '.jsx', '.mjs', '.cjs', '.py', '.go', '.rs', '.java', '.rb']);

const nodes = new Map(); // id -> node
const edges = [];
function addNode(id, type, extra = {}) {
  if (!nodes.has(id)) nodes.set(id, { id, type, ...extra });
  else Object.assign(nodes.get(id), extra);
  return nodes.get(id);
}
function addEdge(from, to, type, extra = {}) { edges.push({ from, to, type, ...extra }); }

// ─── Walk ───
function walk(dir, acc = []) {
  let entries;
  try { entries = readdirSync(dir, { withFileTypes: true }); } catch { return acc; }
  for (const e of entries) {
    if (e.name.startsWith('.') && e.name !== '.env' && !e.name.startsWith('.env.')) {
      if (e.isDirectory()) continue; // pula dotdirs (menos .env já tratado)
    }
    const full = join(dir, e.name);
    if (e.isDirectory()) {
      if (IGNORE_DIRS.has(e.name)) continue;
      walk(full, acc);
    } else {
      acc.push(full);
    }
  }
  return acc;
}

const files = walk(ROOT);
const rel = (f) => relative(ROOT, f).split(sep).join('/');

// ─── Heurística: um caminho é "interno" (não deve aceitar chamada externa)? ───
function isInternalPath(p) {
  return /(^|\/)(internal|worker|workers|jobs|grpc|rpc|consumer|consumers|cron|tasks?)(\/|\.|$)/i.test(p);
}

// ─── Extração por arquivo de código ───
const IMPORT_RE = [
  /import\s+(?:[^'"]*?\s+from\s+)?['"]([^'"]+)['"]/g, // ES import
  /require\(\s*['"]([^'"]+)['"]\s*\)/g,               // CJS require
  /^\s*from\s+([\w.]+)\s+import\b/gm,                 // Python from x import
  /^\s*import\s+([\w.]+)/gm,                          // Python import x
];
// Rotas HTTP (express/fastify/nest/flask/fastapi). {re, m:idx-metodo, p:idx-path}
// Express/fastify: qualquer identificador .metodo('/path') — path DEVE começar com
// '/' (filtra falso-positivo tipo map.get('key')). Pega app/router/fastify/internalApi/etc.
const ROUTE_RES = [
  { re: /\b[A-Za-z_$][\w$]*\.(get|post|put|delete|patch|options|head)\s*\(\s*['"`](\/[^'"`]*)['"`]/gi, m: 1, p: 2 },
  { re: /@(Get|Post|Put|Delete|Patch)\s*\(\s*['"`]?([^'"`)]*)['"`]?\s*\)/g, m: 1, p: 2 }, // Nest decorators
  { re: /@(?:app|router|blueprint|bp)\.route\s*\(\s*['"`](\/[^'"`]*)['"`]/gi, m: 0, p: 1 }, // flask @app.route
];
const ENV_RES = [
  /process\.env\.([A-Z_][A-Z0-9_]*)/g,
  /process\.env\[\s*['"]([A-Z_][A-Z0-9_]*)['"]\s*\]/g,
  /os\.environ(?:\.get)?\(?\[?\s*['"]([A-Z_][A-Z0-9_]*)['"]/g,
];
const WORKER_RE = /(Worker|WorkerSettings|@Processor|bull|bullmq|celery|sidekiq|@nestjs\/bull|arq|rq\.Queue|kafka|rabbitmq|amqplib|sqs)/i;

let endpointCount = 0;
for (const f of files) {
  const r = rel(f);
  const ext = f.slice(f.lastIndexOf('.'));
  if (!SRC_EXT.has(ext)) continue;
  let src;
  try { src = readFileSync(f, 'utf8'); } catch { continue; }
  if (src.length > 600_000) continue; // pula arquivos gigantes
  addNode('file:' + r, 'file', { path: r, internal: isInternalPath(r) });

  // imports
  for (const re of IMPORT_RE) {
    re.lastIndex = 0; let m;
    while ((m = re.exec(src))) {
      const spec = m[1];
      const isRelative = spec.startsWith('.') || spec.startsWith('/');
      if (isRelative) {
        addEdge('file:' + r, 'file:' + normalizeRel(r, spec), 'imports');
      } else {
        const pkg = spec.startsWith('@') ? spec.split('/').slice(0, 2).join('/') : spec.split('/')[0];
        addNode('pkg:' + pkg, 'package', { name: pkg });
        addEdge('file:' + r, 'pkg:' + pkg, 'imports');
      }
    }
  }
  // endpoints
  for (const spec of ROUTE_RES) {
    spec.re.lastIndex = 0; let m;
    while ((m = spec.re.exec(src))) {
      const method = spec.m === 0 ? 'ANY' : (m[spec.m] || 'get').toUpperCase();
      const path = m[spec.p] || '/';
      const internal = isInternalPath(r);
      const id = `ep:${method} ${path}@${r}`;
      addNode(id, 'endpoint', { method, path, file: r, internal });
      addEdge('file:' + r, id, 'exposes');
      endpointCount++;
    }
  }
  // env usage
  for (const re of ENV_RES) {
    re.lastIndex = 0; let m;
    while ((m = re.exec(src))) {
      const key = m[1];
      addNode('env:' + key, 'env', { name: key });
      addEdge('file:' + r, 'env:' + key, 'uses_env');
    }
  }
  // worker/queue
  if (WORKER_RE.test(src)) {
    addNode('worker:' + r, 'worker', { file: r });
    addEdge('file:' + r, 'worker:' + r, 'exposes');
  }
}

function normalizeRel(fromRel, spec) {
  const parts = fromRel.split('/').slice(0, -1);
  for (const seg of spec.split('/')) {
    if (seg === '.' || seg === '') continue;
    if (seg === '..') parts.pop();
    else parts.push(seg);
  }
  let p = parts.join('/');
  // resolve extensão implícita
  if (!/\.[a-z]+$/i.test(p)) {
    for (const e of ['.ts', '.tsx', '.js', '.jsx', '.py', '/index.ts', '/index.js']) {
      if (existsSync(join(ROOT, p + e))) { p += e; break; }
    }
  }
  return p;
}

// ─── docker-compose: serviços + portas + depends_on (parse leve, sem deps) ───
for (const name of ['docker-compose.yml', 'docker-compose.yaml', 'compose.yml', 'compose.yaml']) {
  const p = join(ROOT, name);
  if (!existsSync(p)) continue;
  parseCompose(readFileSync(p, 'utf8'));
  break;
}
function parseCompose(txt) {
  const lines = txt.split('\n');
  let inServices = false, cur = null, curIndent = 0, inPorts = false, published = false, dependsList = [];
  const flush = () => {
    if (cur) {
      addNode('svc:' + cur, 'service', { name: cur, exposed: published, internal: !published });
      for (const d of dependsList) addEdge('svc:' + cur, 'svc:' + d, 'depends_on');
    }
    published = false; dependsList = []; inPorts = false;
  };
  for (const line of lines) {
    if (/^services:\s*$/.test(line)) { inServices = true; continue; }
    if (!inServices) continue;
    if (/^\S/.test(line) && !/^services:/.test(line)) { flush(); inServices = false; continue; } // saiu do bloco
    const m = line.match(/^(\s+)([A-Za-z0-9._-]+):\s*$/);
    if (m && m[1].length <= 2) { flush(); cur = m[2]; curIndent = m[1].length; inPorts = false; continue; }
    if (/^\s+ports:\s*$/.test(line)) { inPorts = true; continue; }
    if (inPorts && /^\s*-\s*['"]?\d+[:\d]/.test(line)) { published = true; continue; }
    if (/^\s+depends_on:/.test(line)) { const inl = line.match(/\[([^\]]+)\]/); if (inl) dependsList.push(...inl[1].split(',').map((s) => s.trim().replace(/['"]/g, ''))); continue; }
    if (/^\s+-\s+[A-Za-z0-9._-]+\s*$/.test(line) && dependsList !== null) { const d = line.trim().replace(/^-\s*/, ''); if (d && !d.includes(':')) dependsList.push(d); }
    if (/^\s+\w/.test(line) && !/^\s+-/.test(line)) inPorts = false;
  }
  flush();
}

// ─── .env keys (só nomes, nunca valores) ───
for (const f of files) {
  const b = basename(f);
  if (b === '.env' || b.startsWith('.env.')) {
    let src; try { src = readFileSync(f, 'utf8'); } catch { continue; }
    for (const line of src.split('\n')) {
      const m = line.match(/^\s*([A-Z_][A-Z0-9_]*)\s*=/);
      if (m) addNode('env:' + m[1], 'env', { name: m[1], declared: true });
    }
  }
}

// ─── Prisma models ───
const prismaPath = join(ROOT, 'prisma', 'schema.prisma');
if (existsSync(prismaPath)) {
  const src = readFileSync(prismaPath, 'utf8');
  const re = /model\s+(\w+)\s*\{/g; let m;
  while ((m = re.exec(src))) addNode('model:' + m[1], 'model', { name: m[1] });
}

// ─── Superfície: externo (aceita chamada externa) × interno ───
const nodeList = [...nodes.values()];
const external = [];
const internal = [];
for (const n of nodeList) {
  if (n.type === 'endpoint') (n.internal ? internal : external).push(n.id);
  if (n.type === 'service') (n.exposed ? external : internal).push(n.id);
  if (n.type === 'worker') internal.push(n.id);
}

const byType = {};
for (const n of nodeList) byType[n.type] = (byType[n.type] || 0) + 1;

const graph = {
  schema: 'blindar/graph@v1',
  built_at: process.env.BLINDAR_NOW || new Date().toISOString(),
  root: ROOT === '.' ? '.' : rel(ROOT),
  stats: {
    files: byType.file || 0,
    packages: byType.package || 0,
    endpoints: byType.endpoint || 0,
    services: byType.service || 0,
    workers: byType.worker || 0,
    models: byType.model || 0,
    env_keys: byType.env || 0,
    edges: edges.length,
    external_surface: external.length,
    internal_surface: internal.length,
  },
  surface: { external, internal },
  nodes: nodeList,
  edges,
};

const out = JSON.stringify(graph, values.json ? undefined : null, values.json ? 0 : 2);
mkdirSync(join(ROOT, '.blindar'), { recursive: true });
const outPath = values.out.startsWith('/') || /^[A-Za-z]:/.test(values.out) ? values.out : join(ROOT, values.out);
writeFileSync(outPath, out);

if (!values.json) {
  console.log(`blindar graph → ${outPath}`);
  console.log(`  files=${graph.stats.files} endpoints=${graph.stats.endpoints} services=${graph.stats.services} workers=${graph.stats.workers} models=${graph.stats.models}`);
  console.log(`  superfície: ${external.length} externa / ${internal.length} interna`);
} else {
  process.stdout.write(out);
}
