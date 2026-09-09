#!/usr/bin/env node
// Separar "entrou neste ciclo" de "baseline já aceito" é o que decide o GO.
//
// O `.accept-risk.md` sempre existiu e nada o lia: a cada rodada o blindar
// re-listava tudo como novo, e a triagem era manual — medido no FastList
// (set/2026), duas rodadas seguidas re-derivando o mesmo baseline.
//
// Este teste fixa as quatro regras que fazem a reconciliação valer alguma coisa:
//
//   1. a impressão digital é estável entre rodadas e sobrevive a mudança de
//      número de linha, mas NÃO é a mesma para outro arquivo ou outra mensagem;
//   2. achado com `fp` registrado no aceite para de contar como novo;
//   3. achado SEM `fp` conta como novo — o default do desconhecido não pode ser
//      "já foi aceito";
//   4. crit aceito não vira verde limpo: rebaixa para CONDITIONAL GO e sai
//      nomeado. Se aceite e ausência ficarem indistinguíveis, o arquivo de
//      aceite vira o lugar onde se esconde crit.
//
// Roda: node tests/accept-risk-reconcile.test.mjs

import { execFileSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = join(__dirname, '..');
const CHECKS = join(ROOT, 'templates', 'checks');
const LIB = join(CHECKS, '_lib.sh');
const GATE = join(CHECKS, 'check-release-gates.sh');

let ok = 0, fail = 0;
const t = (name, cond, extra = '') => {
  if (cond) { ok++; console.log('  ok  - ' + name); }
  else { fail++; console.log('  FAIL- ' + name + (extra ? ` (${extra})` : '')); }
};

const q = (p) => JSON.stringify(p);
const sh = (script, cwd) =>
  execFileSync('bash', ['-c', script], { cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });

const work = mkdtempSync(join(tmpdir(), 'blindar-accept-'));

// ─── findings com fingerprint ───
const semear = (dir) => {
  mkdirSync(dir, { recursive: true });
  sh([
    'BLINDAR_AGENT=check-security',
    'source ' + q(LIB),
    'add_finding crit "segredo hardcoded no repo" src/config.ts 9',
    'add_finding high "cors aberto" src/app.ts 3',
    'emit_result check-security failed 1 >/dev/null 2>&1',
  ].join('\n'), dir);
  return JSON.parse(readFileSync(join(dir, '.blindar', 'results', 'check-security.json'), 'utf8'));
};

const proj = join(work, 'p1');
const res = semear(proj);
const [critF, highF] = res.findings;

t('todo finding sai com fp de 8 hex', res.findings.every((f) => /^[0-9a-f]{8}$/.test(f.fp)),
  JSON.stringify(res.findings.map((f) => f.fp)));
t('fps de achados diferentes não colidem', critF.fp !== highF.fp);

// mesma mensagem e mesmo arquivo, linha diferente -> mesma impressão digital
const mesmaLinhaOutra = sh(
  'BLINDAR_AGENT=check-security\nsource ' + q(LIB) +
  '\nfinding_fp check-security src/config.ts "segredo hardcoded no repo"', proj).trim();
t('fp sobrevive a mudança de número de linha', mesmaLinhaOutra === critF.fp,
  `${mesmaLinhaOutra} vs ${critF.fp}`);
const outroArquivo = sh(
  'source ' + q(LIB) + '\nfinding_fp check-security src/outro.ts "segredo hardcoded no repo"', proj).trim();
t('fp muda quando o arquivo muda', outroArquivo !== critF.fp);

// ─── gate sem aceite: crit é novo e bloqueia ───
const semAceite = sh('bash ' + q(GATE) + ' 2>&1 || true', proj);
t('sem arquivo de aceite, o crit conta como NOVO e bloqueia',
  /BLOCKED/.test(semAceite) && /1 crit NOVO/.test(semAceite),
  semAceite.split('\n').find((l) => l.includes('SECURITY')) || '');
const g1 = JSON.parse(readFileSync(join(proj, '.blindar', 'gates.json'), 'utf8'));
t('gates.json separa novo de aceito', g1.findings && g1.findings.crit_novo === 1 && g1.findings.crit_aceito === 0,
  JSON.stringify(g1.findings));
t('veredito é NO-GO com crit novo', g1.verdict === 'NO-GO', g1.verdict);

// ─── com aceite por fingerprint ───
writeFileSync(join(proj, '.blindar', 'accept-risk.md'), [
  '# Riscos aceitos',
  '',
  '## RISK-001 — chave de sandbox',
  '- **Severidade**: crit',
  '- **fp**: fp:' + critF.fp,
  '- **Por que aceito**: chave sem valor fora do ambiente de teste',
  '',
].join('\n'));

const comAceite = sh('bash ' + q(GATE) + ' 2>&1 || true', proj);
const g2 = JSON.parse(readFileSync(join(proj, '.blindar', 'gates.json'), 'utf8'));
t('crit com fp aceito para de contar como novo',
  g2.findings.crit_novo === 0 && g2.findings.crit_aceito === 1, JSON.stringify(g2.findings));
t('o high sem aceite continua novo', g2.findings.high_novo === 1, JSON.stringify(g2.findings));
t('SECURITY sai de BLOCKED e vira PASS WITH WARNINGS',
  /SECURITY\s+PASS WITH WARNINGS/.test(comAceite),
  comAceite.split('\n').find((l) => l.includes('SECURITY')) || '');
t('crit aceito NÃO vira GO limpo — cai para CONDITIONAL GO',
  g2.verdict === 'CONDITIONAL GO', g2.verdict);
t('o aceite sai nomeado no relatório, não silencioso',
  comAceite.includes('accept-risk.md') && /1 crit aceito/.test(comAceite));
t('gates.json registra qual arquivo de aceite foi lido',
  (g2.findings.accept_file || '').endsWith('accept-risk.md'), g2.findings.accept_file);

// ─── aceite sem fp não casa nada ───
const proj2 = join(work, 'p2');
semear(proj2);
writeFileSync(join(proj2, '.blindar', 'accept-risk.md'), [
  '# Riscos aceitos',
  '',
  '## RISK-001 — segredo hardcoded no repo',
  '- **Severidade**: crit',
  '- **Por que aceito**: escrito em português e mais nada',
  '',
].join('\n'));
const semFp = sh('bash ' + q(GATE) + ' 2>&1 || true', proj2);
const g3 = JSON.parse(readFileSync(join(proj2, '.blindar', 'gates.json'), 'utf8'));
t('aceite sem fp não silencia o achado', g3.findings.crit_novo === 1, JSON.stringify(g3.findings));
t('e o gate diz por que não casou', /fp:xxxxxxxx/.test(semFp));

// ─── schemas ───
const gs = JSON.parse(readFileSync(join(ROOT, 'schemas', 'gates.schema.json'), 'utf8'));
t('gates.schema descreve o bloco findings', !!gs.properties.findings);
const cs = JSON.parse(readFileSync(join(ROOT, 'schemas', 'check-result.schema.json'), 'utf8'));
t('check-result.schema descreve o fp', !!cs.properties.findings.items.properties.fp);

// ─── reuso de playbook só quando nada mudou ───
const runner = readFileSync(join(ROOT, 'scripts', 'blindar-run.sh'), 'utf8');
t('blindar-run.sh oferece --reuse-unchanged', /--reuse-unchanged\)/.test(runner));
t('o reuso exige diff vazio, não escopo adivinhado',
  /git diff --name-only/.test(runner) && /git merge-base --is-ancestor/.test(runner));
t('os dois caminhos de execução reusam igual',
  (runner.match(/pode_reusar/g) || []).length >= 3);

rmSync(work, { recursive: true, force: true });

console.log('\n' + ok + ' ok, ' + fail + ' fail');
process.exit(fail === 0 ? 0 : 1);
