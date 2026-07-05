#!/usr/bin/env node
// Prova o intelligence-globs (v0.45): supressão de falso-positivo POR AGENTE via
// .blindar/intelligence.yml, sem editar o check. Mesmo código vulnerável:
//   sem yml  → check dispara (failed)
//   com yml suprimindo o path → check cala (passed)
import { execFileSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const CHECK = join(__dirname, '..', 'templates', 'checks', 'check-cors-csrf.sh');
let ok = 0, fail = 0;
const t = (n, c) => { if (c) { ok++; console.log('  ok  - ' + n); } else { fail++; console.log('  FAIL- ' + n); } };

function mkproj() {
  const d = mkdtempSync(join(tmpdir(), 'blindar-intel-'));
  mkdirSync(join(d, 'legacy'), { recursive: true });
  // CORS '*' — vulnerável — dentro de legacy/
  writeFileSync(join(d, 'legacy', 'server.ts'), "import cors from 'cors';\napp.use(cors({ origin: '*', credentials: true }));\n");
  return d;
}
function run(cwd) {
  try { execFileSync('bash', [CHECK], { cwd, stdio: 'pipe' }); return 0; }
  catch (e) { return e.status || 1; }
}

// 1. sem intelligence.yml → dispara (CORS '*' em legacy/)
const d1 = mkproj();
t('sem intelligence.yml → check-cors-csrf dispara (exit 1)', run(d1) === 1);

// 2. com intelligence.yml suprimindo legacy/** → cala
const d2 = mkproj();
mkdirSync(join(d2, '.blindar'), { recursive: true });
writeFileSync(join(d2, '.blindar', 'intelligence.yml'),
  'ignore_globs:\n  check-cors-csrf:\n    - "legacy/**"\n');
t('com intelligence.yml (legacy/** suprimido) → check-cors-csrf cala (exit 0)', run(d2) === 0);

// 3. yml suprimindo OUTRO agente não afeta este → ainda dispara
const d3 = mkproj();
mkdirSync(join(d3, '.blindar'), { recursive: true });
writeFileSync(join(d3, '.blindar', 'intelligence.yml'),
  'ignore_globs:\n  check-rate-limit:\n    - "legacy/**"\n');
t('supressão de outro agente não vaza → ainda dispara (exit 1)', run(d3) === 1);

for (const d of [d1, d2, d3]) { try { rmSync(d, { recursive: true, force: true }); } catch {} }
console.log(`\n${ok} ok, ${fail} fail`);
process.exit(fail === 0 ? 0 : 1);
