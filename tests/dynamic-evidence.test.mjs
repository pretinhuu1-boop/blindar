#!/usr/bin/env node
// Contrato da camada DINÂMICA (v0.79.0).
//
// Existe porque a v0.79 adiciona um estado novo ao vocabulário do blindar —
// "exercitei o sistema no ar" x "li o repositório" — e um estado novo que
// ninguém testa é um estado que apodrece. Foram exatamente checks sem par de
// fixture que carregaram os falsos negativos históricos deste projeto.
//
// Este arquivo prova quatro coisas, cada uma contra execução real:
//
//   1. Check dinâmico SEM alvo não sai 'passed'. Sai 'skipped', com motivo.
//   2. Check dinâmico COM alvo defeituoso acha o defeito e marca exercised.
//   3. Check dinâmico COM alvo correto fica calado (controle negativo do par).
//   4. O gate distingue PASS de NOT EXERCISED conforme houve ou não exercício.
//
// Roda: node tests/dynamic-evidence.test.mjs

import { spawn, spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = join(__dirname, '..');
const CHECKS = join(ROOT, 'templates', 'checks');

let ok = 0, fail = 0;
const t = (name, cond, extra = '') => {
  if (cond) { ok++; console.log('  ok  - ' + name); }
  else { fail++; console.log('  FAIL- ' + name + (extra ? ` (${extra})` : '')); }
};

// ── Servidores de teste: o par vulneravel/limpo, em runtime ─────────────────
// O fixture de disco prova o check estatico. Para o dinamico, o "fixture" e um
// processo que responde errado — nao ha como testar de outro jeito.
//
// Precisa ser PROCESSO separado: o teste usa spawnSync para rodar os checks, e
// spawnSync bloqueia o event loop. Um servidor no mesmo Node ficaria sem
// aceitar conexao durante a medicao, e todo probe voltaria 000 — a primeira
// versao deste teste "provou" assim que os checks nao exercitavam nada.
function startServer(mode) {
  const child = spawn(process.execPath, [join(__dirname, 'fixtures', 'dyn-server.mjs'), mode], {
    stdio: ['ignore', 'pipe', 'ignore'],
  });
  return new Promise((resolve, reject) => {
    const prazo = setTimeout(() => reject(new Error('servidor ' + mode + ' nao ficou pronto')), 10000);
    child.stdout.on('data', (buf) => {
      const m = String(buf).match(/READY (\d+)/);
      if (m) { clearTimeout(prazo); resolve({ child, port: Number(m[1]) }); }
    });
  });
}

function runCheck(check, cwd, args = []) {
  const r = spawnSync('bash', [join(CHECKS, check), ...args], {
    cwd, encoding: 'utf8', env: { ...process.env, NO_COLOR: '1' },
  });
  let json = null;
  try {
    json = JSON.parse(readFileSync(join(cwd, '.blindar', 'results', check.replace(/\.sh$/, '') + '.json'), 'utf8'));
  } catch (e) { /* sem result é, ele próprio, um resultado do teste */ }
  return { exit: r.status, stdout: r.stdout || '', json };
}

const work = mkdtempSync(join(tmpdir(), 'blindar-dyn-'));

// ── 1. Sem alvo: nunca 'passed' ─────────────────────────────────────────────
console.log('\n── sem alvo: dinamico nao pode sair passed ──');
for (const check of ['check-failure-ux.sh', 'check-load-curve.sh', 'check-deploy-identity.sh',
                     'check-chaos-run.sh', 'check-redteam-origin.sh']) {
  const { json } = runCheck(check, work);
  t(`${check} sem alvo -> skipped`, json && json.status === 'skipped', json && json.status);
  t(`${check} declara evidence_kind=dynamic`, json && json.evidence_kind === 'dynamic', json && json.evidence_kind);
  t(`${check} marca exercised=false com motivo`,
    json && json.exercised === false && typeof json.not_exercised_reason === 'string' && json.not_exercised_reason.length > 0,
    json && String(json.not_exercised_reason));
}

// ── 2 e 3. Com alvo: acha no defeituoso, cala no correto ────────────────────
console.log('\n── com alvo: dispara no defeituoso, cala no correto ──');
const bad = await startServer('bad');
const good = await startServer('good');
try {
  const rb = runCheck('check-failure-ux.sh', work, ['--url', `http://127.0.0.1:${bad.port}`]);
  t('failure-ux exercitou o alvo defeituoso', rb.json && rb.json.exercised === true);
  t('failure-ux reprovou no alvo defeituoso', rb.json && rb.json.status === 'failed', rb.json && rb.json.status);
  const sevs = (rb.json?.findings || []).map((f) => f.severity);
  t('failure-ux achou o vazamento de rastro (crit)', sevs.includes('crit'), sevs.join(','));
  t('failure-ux achou o 500 onde cabia 404 (high)', sevs.includes('high'), sevs.join(','));

  const rg = runCheck('check-failure-ux.sh', work, ['--url', `http://127.0.0.1:${good.port}`]);
  t('failure-ux exercitou o alvo correto', rg.json && rg.json.exercised === true);
  const graves = (rg.json?.findings || []).filter((f) => f.severity === 'crit' || f.severity === 'high');
  t('failure-ux nao inventa crit/high no alvo correto', graves.length === 0,
    graves.map((f) => f.severity + ':' + f.message.slice(0, 40)).join(' | '));

  // deploy-identity: o servidor declara commit 'deadbee', que não é o HEAD deste
  // repositório — divergência é crit, e é o desfecho esperado.
  const rd = runCheck('check-deploy-identity.sh', work, ['--url', `http://127.0.0.1:${good.port}`]);
  const identidade = rd.json && rd.json.exercised === true;
  t('deploy-identity exercitou o alvo', identidade || rd.json?.status === 'skipped',
    rd.json && (rd.json.not_exercised_reason || rd.json.status));
} finally {
  bad.child.kill();
  good.child.kill();
}

// ── 4. Gate: PASS x NOT EXERCISED ───────────────────────────────────────────
console.log('\n── gate: estatico passando nao fecha dimensao dinamica ──');
const gateDir = mkdtempSync(join(tmpdir(), 'blindar-gate-'));
mkdirSync(join(gateDir, '.blindar', 'results'), { recursive: true });
const res = (agent, extra) => writeFileSync(
  join(gateDir, '.blindar', 'results', agent + '.json'),
  JSON.stringify({
    schema: 'blindar/check-result@v1', agent, status: 'passed', exit_code: 0,
    missing_tool: null, findings_count: 0, evidence_kind: 'static', exercised: false,
    not_exercised_reason: null, findings: [], ...extra,
  }, null, 2));

const runGate = () => {
  const r = spawnSync('bash', [join(CHECKS, 'check-release-gates.sh')],
    { cwd: gateDir, encoding: 'utf8', env: { ...process.env, NO_COLOR: '1' } });
  let gates = null;
  try { gates = JSON.parse(readFileSync(join(gateDir, '.blindar', 'gates.json'), 'utf8')); } catch (e) {}
  return { out: r.stdout || '', gates };
};
const statusOf = (g, name) => (g?.gates || []).find((x) => x.gate === name)?.status;

res('check-fallback-resilience');
let g1 = runGate();
t('RESILIENCE so com estatico -> NOT EXERCISED', statusOf(g1.gates, 'RESILIENCE') === 'NOT EXERCISED',
  statusOf(g1.gates, 'RESILIENCE'));
t('NOT EXERCISED conta como warning, nao como GO', g1.gates && g1.gates.verdict !== 'GO', g1.gates?.verdict);

res('check-chaos-run', { evidence_kind: 'dynamic', exercised: true });
let g2 = runGate();
t('RESILIENCE com dinamico exercitado -> PASS', statusOf(g2.gates, 'RESILIENCE') === 'PASS',
  statusOf(g2.gates, 'RESILIENCE'));

res('check-chaos-run', { evidence_kind: 'dynamic', exercised: false, status: 'skipped',
  not_exercised_reason: 'sem alvo' });
let g3 = runGate();
t('dinamico que NAO exercitou nao fecha o gate', statusOf(g3.gates, 'RESILIENCE') === 'NOT EXERCISED',
  statusOf(g3.gates, 'RESILIENCE'));
t('nenhum check novo fica UNMAPPED', !g3.out.includes('sem gate mapeado'),
  g3.out.split('\n').find((l) => l.includes('sem gate mapeado')) || '');

rmSync(work, { recursive: true, force: true });
rmSync(gateDir, { recursive: true, force: true });

console.log('');
console.log(`${ok} ok, ${fail} fail`);
process.exit(fail > 0 ? 1 : 0);
