#!/usr/bin/env node
// Liga o intelligence-globs (v0.45) em todos os checks determinísticos.
// Após a declaração do array de exclusão (IGNORE / IGNORE_GLOBS / RG_IGNORE),
// insere `load_intelligence_globs "$BLINDAR_AGENT"` e anexa "${INTEL_GLOBS[@]}" a
// cada uso "${<ARRAY>[@]}". Idempotente (pula quem já tem load_intelligence_globs).
// Sucede o _patch-intel-globs.js (que só existia na cópia instalada) — agora
// versionado no dev e verificado pelo gate. Uso: node scripts/wire-intel-globs.js [--dry]
import { readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';

const __dirname = dirname(fileURLToPath(import.meta.url));
const { values } = parseArgs({
  options: { dir: { type: 'string', default: join(__dirname, '..', 'templates', 'checks') }, dry: { type: 'boolean', default: false } },
});

const files = readdirSync(values.dir).filter((f) => /^check-.*\.sh$/.test(f) && !f.endsWith('.api.sh'));
let changed = 0; const summary = [];
for (const f of files) {
  const p = join(values.dir, f);
  let src = readFileSync(p, 'utf8');
  if (src.includes('load_intelligence_globs')) continue; // idempotente
  // Primeira declaração de array de exclusão (multi-linha ok: [^)] inclui \n)
  const m = src.match(/^([ \t]*)((?:RG_)?IGNORE(?:_GLOBS)?)=\([^)]*\)[ \t]*\r?\n/m);
  if (!m) continue; // check sem array de ignore → nada a ligar
  const indent = m[1]; const arr = m[2];
  const idx = m.index + m[0].length;
  src = src.slice(0, idx) + `${indent}load_intelligence_globs "$BLINDAR_AGENT"\n` + src.slice(idx);
  const usage = new RegExp(`"\\$\\{${arr}\\[@\\]\\}"`, 'g');
  src = src.replace(usage, `"\${${arr}[@]}" "\${INTEL_GLOBS[@]}"`);
  if (!values.dry) writeFileSync(p, src);
  changed++; summary.push(`  ${f} (${arr})`);
}
console.log(`wire-intel-globs: ${changed}/${files.length} ${values.dry ? '(dry-run)' : 'ligado(s)'}`);
summary.forEach((s) => console.log(s));
