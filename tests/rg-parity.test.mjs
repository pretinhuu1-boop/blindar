#!/usr/bin/env node
// Paridade ripgrep real × fallback de grep do _lib.sh.
//
// POR QUE ESTE TESTE EXISTE
// O _lib.sh reimplementa o ripgrep sobre grep pra quando o binário falta. As
// duas implementações NÃO tinham as mesmas semânticas, e o fallback era
// sistematicamente mais tolerante: aceitava `--type tsx|jsx|scss|prisma|env`
// (que o rg real rejeita com erro 2) e `'!glob'` solto como exclusão (que o rg
// real trata como CAMINHO). Com `2>/dev/null` + `|| true`, o erro sumia e o
// check reportava "passed" sem ter varrido nada.
//
// Resultado: 71 ocorrências de falso-negativo silencioso, CI vermelha por 5
// semanas, e checks contando como cobertura sem testar coisa alguma.
//
// Este teste falha no dia em que alguém reintroduz a divergência.
// Roda: node tests/rg-parity.test.mjs

import { execFileSync } from 'node:child_process';
import { readdirSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = join(__dirname, '..');
const CHECKS = join(ROOT, 'templates', 'checks');

let ok = 0, fail = 0;
const t = (name, cond, extra = '') => {
  if (cond) { ok++; console.log('  ok  - ' + name); }
  else { fail++; console.log('  FAIL- ' + name + (extra ? `\n         ${extra}` : '')); }
};

const shFiles = readdirSync(CHECKS).filter((f) => f.endsWith('.sh'));
const lib = readFileSync(join(CHECKS, '_lib.sh'), 'utf8');

// ── 1. Todo --type usado precisa existir no ripgrep real ───────────────────
// Tipos que o _lib.sh injeta via --type-add contam como válidos.
let realTypes = null;
try {
  realTypes = new Set(
    execFileSync('rg', ['--type-list'], { encoding: 'utf8' })
      .split('\n').map((l) => l.split(':')[0].trim()).filter(Boolean),
  );
} catch { /* rg ausente: não dá pra validar o vocabulário real */ }

const added = new Set([...lib.matchAll(/--type-add\s+'([a-zA-Z0-9_]+):/g)].map((m) => m[1]));

if (realTypes) {
  const used = new Map(); // tipo → arquivos
  for (const f of shFiles) {
    const src = readFileSync(join(CHECKS, f), 'utf8');
    for (const m of src.matchAll(/--type\s+([a-zA-Z0-9_]+)/g)) {
      if (!used.has(m[1])) used.set(m[1], new Set());
      used.get(m[1]).add(f);
    }
  }
  const invalid = [...used.entries()].filter(([ty]) => !realTypes.has(ty) && !added.has(ty));
  t(
    `todo --type usado existe no ripgrep real (ou vem de --type-add)`,
    invalid.length === 0,
    invalid.map(([ty, fs]) => `${ty} → ${[...fs].slice(0, 4).join(', ')}`).join('\n         '),
  );
  t('os tipos customizados do _lib.sh são os esperados', added.has('prisma') && added.has('env'), `--type-add encontrados: ${[...added].join(', ') || 'nenhum'}`);
} else {
  console.log('  SKIP- validação de --type (ripgrep ausente)');
}

// ── 1b. O wrapper precisa blindar stdin e o path-mangling do MSYS ──────────
// rg lê o STDIN quando ele não é TTY e nenhum path é passado. Como os checks
// chamam `rg PADRÃO --type ts` sem path, rodar sob pipe (CI, | tee, cron,
// execFileSync) fazia o rg buscar num pipe VAZIO — 74 checks cegos de uma vez.
// E no Git Bash o MSYS reescreve argumentos que parecem caminho POSIX, então
// um padrão como "/health/live" virava "C:/Program Files/Git/health/live".
{
  const wrapper = lib.slice(lib.indexOf('BLINDAR_RG_BIN'));
  t('wrapper do rg redireciona stdin (</dev/null)', /<\s*\/dev\/null/.test(wrapper),
    'sem isto o rg lê o pipe vazio e não varre o cwd');
  t('wrapper do rg desliga o path-mangling do MSYS', /MSYS2_ARG_CONV_EXCL|MSYS_NO_PATHCONV/.test(wrapper),
    'sem isto padrões iniciados por / são reescritos antes de chegar ao rg.exe');
}

// ── 2. Nenhum glob de exclusão solto em array ──────────────────────────────
// '!glob' sem -g/--glob vira CAMINHO pro rg real → não sobra caminho válido →
// varre nada, sai 2, e o check passa sempre.
// Varre TODA linha, não só o interior de arrays: os globs aparecem tanto em
// `IGNORE=(...)` quanto INLINE no meio da chamada do rg. A primeira versão
// deste teste só olhava arrays e deixou passar 5 checks com a forma inline.
{
  const offenders = [];
  for (const f of shFiles) {
    if (f === '_lib.sh') continue; // contém `'!'*)` como padrão de case, legítimo
    readFileSync(join(CHECKS, f), 'utf8').split('\n').forEach((line, i) => {
      // Comentários explicam a armadilha e citam a forma errada — não são código.
      const code = line.replace(/(^|\s)#.*$/, '');
      if (!/\brg\b|=\(/.test(code)) return;
      // Remove prefixos "NAME=(" pra que o 1º elemento não colida com eles.
      const norm = code.replace(/\b[A-Za-z_][A-Za-z0-9_]*=\(/g, ' ');
      for (const m of norm.matchAll(/(\S+\s+)?'![^']*'/g)) {
        const prev = (m[1] || '').trim();
        if (prev !== '-g' && prev !== '--glob') offenders.push(`${f}:${i + 1}  ${m[0].trim().slice(0, 40)}`);
      }
    });
  }
  t('nenhum glob de exclusão passado sem -g/--glob (array OU inline)',
    offenders.length === 0, offenders.slice(0, 10).join('\n         '));
}

// ── 3. Erro do rg não pode ser mascarado silenciosamente ───────────────────
// `2>/dev/null` + `|| true` juntos transformam "rg falhou" em "nada encontrado".
// Não é proibido, mas o check precisa validar a saída de algum jeito — aqui só
// contamos pra que o número não cresça sem revisão.
{
  let masked = 0;
  for (const f of shFiles) {
    const src = readFileSync(join(CHECKS, f), 'utf8');
    for (const line of src.split('\n')) {
      if (/\brg\b/.test(line) && line.includes('2>/dev/null') && /\|\|\s*true/.test(line)) masked += 1;
    }
  }
  // Baseline registrado no dia em que a família de bugs foi fechada.
  t(`invocações de rg com erro mascarado não aumentaram (${masked} ≤ 120)`, masked <= 120, `atual=${masked}`);
}

// ── 4. Paridade de runtime: mesmo veredito com e sem ripgrep ───────────────
// Roda o mesmo check nas duas implementações e exige status idêntico.
const PAIRS = [
  ['check-mock-killer.sh', 'project-with-mocks', 'failed'],
  ['check-mock-killer.sh', 'clean-project', 'passed'],
  ['check-config-externalization.sh', 'project-with-secrets', 'failed'],
  ['check-client-open-redirect.sh', 'project-openredir-bad', 'failed'],
];

function statusOf(check, fixture, stripRg) {
  const cwd = join(ROOT, 'tests', 'fixtures', fixture);
  const env = { ...process.env };
  if (stripRg) {
    // Remove do PATH só o diretório do binário rg — grep e coreutils ficam.
    let rgDir = null;
    try { rgDir = dirname(execFileSync('bash', ['-lc', 'type -P rg'], { encoding: 'utf8' }).trim()); } catch {}
    if (rgDir) {
      const sep = process.platform === 'win32' ? ';' : ':';
      env.PATH = (env.PATH || '').split(sep).filter((p) => p && !p.includes('ripgrep')).join(sep);
    }
  }
  try {
    execFileSync('bash', [join(CHECKS, check)], { cwd, env, stdio: 'pipe' });
  } catch { /* exit≠0 é esperado quando falha */ }
  let st = 'nojson';
  try {
    const j = JSON.parse(readFileSync(join(cwd, '.blindar', 'results', check.replace(/\.sh$/, '') + '.json'), 'utf8'));
    st = j.status;
  } catch {}
  try { execFileSync('bash', ['-lc', `rm -rf "${cwd.replace(/\\/g, '/')}/.blindar"`]); } catch {}
  return st;
}

for (const [check, fixture, expected] of PAIRS) {
  const real = statusOf(check, fixture, false);
  const fb = statusOf(check, fixture, true);
  t(`${check} / ${fixture}: real=${real} fallback=${fb} (esperado ${expected})`,
    real === expected && fb === expected,
    real !== fb ? 'DIVERGÊNCIA entre ripgrep real e fallback de grep' : `ambos deram ${real}`);
}

console.log(`\n${ok} ok, ${fail} fail`);
process.exit(fail === 0 ? 0 : 1);
