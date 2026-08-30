#!/usr/bin/env node
// Insumo de fixture precisa CHEGAR no clone limpo.
//
// Existe por causa de um defeito que viveu no repositório desde que foi
// escrito, e que nenhum teste pegava: o `.gitignore` ignorava
// `tests/fixtures/**/.blindar/` inteiro — regra correta para a SAÍDA que os
// checks escrevem ali, e desastrosa para os fixtures cujo INSUMO mora no mesmo
// lugar.
//
// O efeito é o pior modo de falha possível: o par passa na máquina de quem o
// escreveu, e chega sem insumo no clone limpo, onde o check reprova por falta
// de pré-requisito. Quem lê o resultado vê "falso-positivo no fixture limpo" e
// vai procurar o bug no check, que está certo.
//
// Foi assim com o par do `check-wave-guardian`: `run-report.json` nunca foi
// commitado, e o par estava quebrado upstream sem ninguém notar.
//
// Este teste percorre os fixtures registrados em PAIRS e exige que todo arquivo
// dentro deles seja alcançável por um clone — ou seja, não ignorado pelo git.
//
// Roda: node tests/fixtures-versionados.test.mjs

import { spawnSync } from 'node:child_process';
import { readFileSync, readdirSync, statSync, existsSync } from 'node:fs';
import { dirname, join, relative, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = join(__dirname, '..');
const FIXTURES = join(__dirname, 'fixtures');

let ok = 0, fail = 0;
const t = (name, cond, extra = '') => {
  if (cond) { ok++; console.log('  ok  - ' + name); }
  else { fail++; console.log('  FAIL- ' + name + (extra ? ` (${extra})` : '')); }
};

// Sem git (tarball, sandbox sem .git) não há o que verificar — e não verificar
// não pode virar aprovação silenciosa, então o teste diz isso em voz alta.
const dentroDeGit = spawnSync('git', ['rev-parse', '--is-inside-work-tree'],
  { cwd: ROOT, encoding: 'utf8' }).stdout?.trim() === 'true';
if (!dentroDeGit) {
  console.log('  ⊘  fora de um repositório git — NÃO VERIFICADO (não é aprovação)');
  console.log('0 ok, 0 fail');
  process.exit(0);
}

// ── Fixtures citados no registro de pares ───────────────────────────────────
// A fonte é o próprio check-selftest.sh: o que ele promete verificar é
// exatamente o que precisa existir no clone.
const selftest = readFileSync(join(ROOT, 'scripts', 'check-selftest.sh'), 'utf8');
const citados = new Set();
for (const linha of selftest.split('\n')) {
  const m = linha.match(/^\s*"([^"]+)"\s*$/);
  if (!m || !m[1].includes('|')) continue;
  const [, vuln, limpo] = m[1].split('|').map((x) => x.trim());
  if (vuln) citados.add(vuln);
  if (limpo) citados.add(limpo);
}
t('o registro de pares cita ao menos 50 fixtures', citados.size >= 50, String(citados.size));

// ── Todo fixture citado existe ──────────────────────────────────────────────
const ausentes = [...citados].filter((f) => !existsSync(join(FIXTURES, f)));
t('todo fixture citado em PAIRS existe em disco', ausentes.length === 0, ausentes.join(' '));

// ── Nenhum arquivo de fixture é invisível para um clone ─────────────────────
function arquivosDe(dir) {
  const out = [];
  for (const nome of readdirSync(dir)) {
    const p = join(dir, nome);
    let st;
    try { st = statSync(p); } catch { continue; }
    if (st.isDirectory()) out.push(...arquivosDe(p));
    else out.push(p);
  }
  return out;
}

// `results/` e os relatórios que os checks ESCREVEM são saída legítima: eles
// aparecem depois de qualquer execução e não fazem parte do fixture. Ignorá-los
// é o comportamento certo, então não entram na conta.
const SAIDA = /(\.blindar[\\/]results[\\/])|(\.blindar[\\/]wave-\d+-guardian\.md$)|(\.blindar[\\/](gates|aggregate|chaos-run|load-curve|deploy-identity|failure-ux|redteam-origin)\.json$)/;

const candidatos = [];
for (const nome of citados) {
  const dir = join(FIXTURES, nome);
  if (!existsSync(dir)) continue;
  for (const f of arquivosDe(dir)) {
    if (SAIDA.test(f)) continue;
    candidatos.push(relative(ROOT, f).split(sep).join('/'));
  }
}
t('há arquivos de fixture para conferir', candidatos.length > 0, String(candidatos.length));

// git check-ignore em lote: sai 0 quando ALGUM caminho é ignorado, e lista quais.
const r = spawnSync('git', ['check-ignore', '--stdin'],
  { cwd: ROOT, input: candidatos.join('\n'), encoding: 'utf8' });
const ignorados = (r.stdout || '').split('\n').map((x) => x.trim()).filter(Boolean);

t('nenhum insumo de fixture é ignorado pelo .gitignore', ignorados.length === 0,
  ignorados.slice(0, 8).join(' ') + (ignorados.length > 8 ? ` (+${ignorados.length - 8})` : ''));

// ── E a saída transiente continua fora ──────────────────────────────────────
// A correção não pode ter aberto a porta para o resultado de cada rodada entrar
// no repositório: seria trocar um problema por outro.
const amostraSaida = 'tests/fixtures/project-negctl-bad/.blindar/results/check-x.json';
const rs = spawnSync('git', ['check-ignore', '-q', amostraSaida], { cwd: ROOT });
t('saída transiente (.blindar/results/) continua ignorada', rs.status === 0,
  'status=' + rs.status);

console.log('');
console.log(`  ${citados.size} fixtures citados · ${candidatos.length} arquivos conferidos`);
console.log(`${ok} ok, ${fail} fail`);
process.exit(fail > 0 ? 1 : 0);
