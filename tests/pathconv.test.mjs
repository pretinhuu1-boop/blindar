#!/usr/bin/env node
// Regressão: path POSIX × binário nativo do Windows (ver docs/BASH-COMPAT.md).
//
// Bug original: `bash scripts/validate.sh <schema> /tmp/cfg.json` no Git Bash
// respondia "[FAIL] JSON invalido" pra um JSON perfeitamente válido. O `[ -f ]`
// passava (bash MSYS entende /tmp), mas o validador (jq/python3) é binário
// NATIVO do Windows e resolvia /tmp/cfg.json como C:\tmp\cfg.json. O ENOENT
// ia pro /dev/null e o script culpava o conteúdo do arquivo.
//
// Roda via tests/run-tests.sh. Exit 0 = ok.
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, existsSync, rmSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const SKILL = join(__dirname, '..');
const VALIDATE = join(SKILL, 'scripts', 'validate.sh');
const GRAPH = join(SKILL, 'scripts', 'graph-build.js');
const SCHEMAS = join(SKILL, 'scripts', 'validate-schemas.js');
const WIN = process.platform === 'win32';

let ok = 0, fail = 0, skip = 0;
const t = (name, cond) => { if (cond) { ok++; console.log('  ok  - ' + name); } else { fail++; console.log('  FAIL- ' + name); } };
const s = (name) => { skip++; console.log('  skip- ' + name); };

const TMP = mkdtempSync(join(tmpdir(), 'blindar-pathconv-'));
const runBash = (args, env = {}) =>
  spawnSync('bash', args, { encoding: 'utf8', env: { ...process.env, ...env } });

try {
  // ─── 1. validate.sh: JSON válido não pode ser reportado como inválido ─────
  const good = join(TMP, 'cfg.json');
  writeFileSync(good, JSON.stringify({ schema: 'blindar/run-report@v1', ok: true }));
  const r1 = runBash([VALIDATE, 'run-report', good]);
  t('validate.sh aceita JSON valido (exit 0)', r1.status === 0);
  t('validate.sh nao acusa "JSON invalido" em arquivo valido',
    !`${r1.stdout}${r1.stderr}`.includes('JSON invalido'));

  // Mesmo arquivo, mas por um path POSIX que só o bash MSYS resolve.
  // É a reprodução literal do bug reportado.
  if (WIN) {
    const posix = execFileSync('cygpath', ['-u', good], { encoding: 'utf8' }).trim();
    const r2 = runBash([VALIDATE, 'run-report', posix], { MSYS_NO_PATHCONV: '1' });
    t(`validate.sh aceita JSON valido em path POSIX (${posix})`, r2.status === 0);
  } else {
    s('path POSIX -> binario nativo (so faz sentido no Windows)');
  }

  // ─── 2. JSON realmente quebrado continua sendo reportado como tal ────────
  const bad = join(TMP, 'bad.json');
  writeFileSync(bad, '{"a": }');
  const r3 = runBash([VALIDATE, 'run-report', bad]);
  const out3 = `${r3.stdout}${r3.stderr}`;
  t('validate.sh rejeita JSON quebrado (exit != 0)', r3.status !== 0);
  t('validate.sh diz "JSON invalido" no caso certo', out3.includes('JSON invalido'));
  // O stderr do validador tem que aparecer — era engolido por 2>/dev/null.
  t('validate.sh imprime o erro real do parser (nao engole stderr)',
    /line 1|column|parse|Expecting|Invalid|invalid/i.test(out3.replace('JSON invalido', '')));

  // ─── 3. Arquivo ausente é "nao encontrado", nunca "JSON invalido" ────────
  const r4 = runBash([VALIDATE, 'run-report', join(TMP, 'nao-existe.json')]);
  const out4 = `${r4.stdout}${r4.stderr}`;
  t('validate.sh distingue arquivo ausente de conteudo invalido',
    r4.status !== 0 && !out4.includes('JSON invalido'));

  // ─── 4. Guard estático: path nunca interpolado no source de outra ling. ──
  // `python3 -c "...open('$FILE')"` é o padrão que causou o bug (e ainda faria
  // "C:\tmp\new.json" virar tab+newline dentro da string Python).
  const src = readFileSync(VALIDATE, 'utf8');
  t('validate.sh nao interpola $FILE dentro do source do python',
    !/open\('\$\{?FILE/.test(src));
  t('validate.sh converte path com cygpath antes do binario nativo',
    src.includes('cygpath'));

  // ─── 5. graph-build.js: --dir errado falha alto, nao vira grafo vazio ────
  const ghost = join(TMP, 'nao-existe-dir');
  const r5 = spawnSync('node', [GRAPH, '--dir', ghost, '--json'], { encoding: 'utf8' });
  t('graph-build.js falha com --dir inexistente (exit 2)', r5.status === 2);
  t('graph-build.js nao emite grafo vazio silencioso', !r5.stdout.includes('"files":0'));
  t('graph-build.js nao cria a arvore do --dir invalido', !existsSync(ghost));

  // E continua funcionando num dir real.
  const real = join(TMP, 'proj');
  mkdirSync(real);
  writeFileSync(join(real, 'a.js'), 'import express from "express";\n');
  const r6 = spawnSync('node', [GRAPH, '--dir', real, '--json'], { encoding: 'utf8' });
  t('graph-build.js segue funcionando em dir valido',
    r6.status === 0 && JSON.parse(r6.stdout).stats.files === 1);

  // ─── 6. validate-schemas.js: --input inexistente é erro de uso (exit 2) ──
  const r7 = spawnSync('node', [SCHEMAS, '--input', join(TMP, 'nada')], { encoding: 'utf8' });
  t('validate-schemas.js falha com --input inexistente (exit 2)', r7.status === 2);
  t('validate-schemas.js mostra o path resolvido no erro',
    /não existe|nao existe/.test(r7.stderr));
} finally {
  rmSync(TMP, { recursive: true, force: true });
}

console.log(`\n${ok} ok, ${fail} fail${skip ? `, ${skip} skip` : ''}`);
process.exit(fail === 0 ? 0 : 1);
