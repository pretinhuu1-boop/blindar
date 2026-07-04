#!/usr/bin/env node
// Testa scripts/load-test.sh: alvo saudável passa o SLO; alvo com 500 falha.
import { spawn, execFileSync } from 'node:child_process';
import { mkdtempSync, writeFileSync, readFileSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const LT = join(__dirname, '..', 'scripts', 'load-test.sh');
let ok = 0, fail = 0;
const t = (n, c) => { if (c) { ok++; console.log('  ok  - ' + n); } else { fail++; console.log('  FAIL- ' + n); } };

const portFile = join(mkdtempSync(join(tmpdir(), 'blindar-lt-')), 'port');
const code = `
const http=require('http'),fs=require('fs');
const s=http.createServer((q,r)=>{ if(q.url.startsWith('/err')){r.writeHead(500);return r.end('e');} r.writeHead(200);r.end('ok'); });
s.listen(0,'127.0.0.1',()=>fs.writeFileSync(${JSON.stringify(portFile)},String(s.address().port)));
`;
const srv = spawn(process.execPath, ['-e', code], { stdio: 'ignore' });
function wait(ms){const e=Date.now()+ms;while(Date.now()<e){if(existsSync(portFile)){const p=readFileSync(portFile,'utf8').trim();if(p)return p;}try{execFileSync(process.execPath,['-e','setTimeout(()=>{},80)']);}catch{}}return null;}
function run(args){ try{ execFileSync('bash',[LT,...args],{stdio:'pipe'}); return 0; } catch(e){ return e.status||1; } }

try {
  const port = wait(5000);
  if (!port) { console.log('  FAIL- mock não subiu'); srv.kill(); process.exit(1); }
  const base = `http://127.0.0.1:${port}`;
  t('alvo saudável dentro do SLO → passa (exit 0)',
    run(['--url', base + '/ok', '--requests', '30', '--concurrency', '10', '--slo-error-pct', '5', '--slo-p95-ms', '5000']) === 0);
  t('alvo com 500 (erro% alto) → falha (exit 1)',
    run(['--url', base + '/err', '--requests', '30', '--concurrency', '10', '--slo-error-pct', '5', '--slo-p95-ms', '5000']) === 1);
} finally { srv.kill(); }

console.log(`\n${ok} ok, ${fail} fail`);
process.exit(fail === 0 ? 0 : 1);
