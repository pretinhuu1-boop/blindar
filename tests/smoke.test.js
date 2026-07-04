#!/usr/bin/env node
// Testa scripts/smoke-run.sh contra um servidor mock (sem docker).
// Prova: (1) passa quando saudável sem 5xx; (2) detecta 500 de runtime;
// (3) detecta boot quebrado (health nunca 200).
// O mock roda em PROCESSO SEPARADO — execFileSync bloqueia o event loop, então
// servidor e runner não podem compartilhar o mesmo processo.
import { spawn, execFileSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, existsSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const SMOKE = join(__dirname, '..', 'scripts', 'smoke-run.sh');

let ok = 0, fail = 0;
const t = (name, cond) => { if (cond) { ok++; console.log('  ok  - ' + name); } else { fail++; console.log('  FAIL- ' + name); } };

const portFile = join(mkdtempSync(join(tmpdir(), 'blindar-port-')), 'port');
const serverCode = `
const http=require('http'),fs=require('fs');
const s=http.createServer((q,r)=>{
  if(q.url==='/health'){r.writeHead(200);return r.end('ok')}
  if(q.url==='/api/ok'){r.writeHead(200);return r.end('[]')}
  if(q.url==='/api/boom'){r.writeHead(500);return r.end('boom')}
  r.writeHead(404);r.end();
});
s.listen(0,'127.0.0.1',()=>fs.writeFileSync(${JSON.stringify(portFile)},String(s.address().port)));
`;
const srv = spawn(process.execPath, ['-e', serverCode], { stdio: 'ignore' });

function waitPort(ms) {
  const end = Date.now() + ms;
  while (Date.now() < end) {
    if (existsSync(portFile)) { const p = readFileSync(portFile, 'utf8').trim(); if (p) return p; }
    try { execFileSync(process.execPath, ['-e', 'setTimeout(()=>{},100)']); } catch {}
  }
  return null;
}
function graphDir(endpoints) {
  const dir = mkdtempSync(join(tmpdir(), 'blindar-smoke-'));
  mkdirSync(join(dir, '.blindar'), { recursive: true });
  writeFileSync(join(dir, '.blindar', 'graph.json'), JSON.stringify({
    schema: 'blindar/graph@v1', built_at: 'x',
    stats: { files: 1, endpoints: endpoints.length, edges: 0, external_surface: endpoints.length, internal_surface: 0 },
    surface: { external: endpoints.map((e) => 'ep:' + e), internal: [] },
    nodes: endpoints.map((p) => ({ id: 'ep:GET ' + p, type: 'endpoint', method: 'GET', path: p, internal: false })),
    edges: [],
  }));
  return dir;
}
function runSmoke(url, cwd) {
  try { execFileSync('bash', [SMOKE, '--url', url, '--timeout', '8'], { cwd, stdio: 'pipe' }); return 0; }
  catch (e) { return e.status || 1; }
}

try {
  const port = waitPort(5000);
  if (!port) { console.log('  FAIL- servidor mock não subiu'); srv.kill(); process.exit(1); }
  const url = `http://127.0.0.1:${port}`;

  t('app saudável sem 5xx → smoke passa (exit 0)', runSmoke(url, graphDir(['/api/ok'])) === 0);
  t('GET que retorna 500 → smoke falha (exit 1)', runSmoke(url, graphDir(['/api/boom'])) === 1);
  t('app que não sobe (health nunca 200) → smoke falha (exit 1)', runSmoke('http://127.0.0.1:1', graphDir(['/api/ok'])) === 1);
} finally {
  srv.kill();
  try { rmSync(dirname(portFile), { recursive: true, force: true }); } catch {}
}
console.log(`\n${ok} ok, ${fail} fail`);
process.exit(fail === 0 ? 0 : 1);
