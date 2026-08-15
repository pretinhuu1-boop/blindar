#!/usr/bin/env node
// Testes do template log-ops: rotação por tamanho, virada do dia, retenção
// (apaga o que deve / preserva hoje e ontem), isolamento entre processos,
// ausência de dado sensível nos arquivos, e comportamento sob disco cheio.
// Roda: node tests/log-ops.test.mjs

import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

import { createLogger } from '../templates/log-ops/logger.mjs';
import { sweep, streamOf, retentionFromEnv } from '../templates/log-ops/retention.mjs';
import { pseudonym, ipNet, ipFields } from '../templates/log-ops/pseudonym.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const LOGGER = join(__dirname, '..', 'templates', 'log-ops', 'logger.mjs');

let ok = 0, fail = 0;
const t = (name, cond, extra = '') => {
  if (cond) { ok++; console.log('  ok  - ' + name); }
  else { fail++; console.log('  FAIL- ' + name + (extra ? ` (${extra})` : '')); }
};
const tmp = () => mkdtempSync(join(tmpdir(), 'logops-'));
const jsonl = (dir, day) => readdirSync(join(dir, day)).filter((f) => f.endsWith('.jsonl'));
const D = (s) => new Date(s);

// Disco saudável INJETADO nos testes que exercitam escrita. Sem isto o teste lê
// o disco da máquina: numa máquina quase cheia o guard de espaço desliga o sink
// de arquivo, nada é escrito, e um teste de ROTAÇÃO falha com ENOENT — acusando
// o código errado. Teste de rotação/redação não pode depender de quanto disco a
// máquina tem sobrando. O caso de disco baixo tem seu próprio teste, que injeta
// o valor baixo de propósito.
const HEALTHY_DISK = () => ({ free: 64 * 1024 ** 3, total: 512 * 1024 ** 3 });

// ── 1. rotação por tamanho ──────────────────────────────────────────────────
{
  const dir = tmp();
  const log = createLogger({ dir, service: 'api', maxBytes: 2000, compress: false, stdout: () => {}, diskFree: HEALTHY_DISK, now: () => D('2026-08-01T10:00:00Z') });
  for (let i = 0; i < 120; i++) log('access', 'http.request.completed', { path: '/v1/orders', status: 200, i });
  log.flush();
  const files = jsonl(dir, '2026-08-01');
  t('rotação: 16MB→2KB gera múltiplos arquivos', files.length > 1, `arquivos=${files.length}`);
  t('rotação: sequência numerada e um arquivo por processo', files.every((f) => /^access-[^-]+-[0-9a-f]{6}-\d{3}\.jsonl$/.test(f)), files[0]);
  const total = files.reduce((n, f) => n + readFileSync(join(dir, '2026-08-01', f), 'utf8').trim().split('\n').length, 0);
  t('rotação: nenhuma linha perdida no corte', total === 120, `linhas=${total}`);
  rmSync(dir, { recursive: true, force: true });
}

// ── 2. virada do dia (UTC) ──────────────────────────────────────────────────
{
  const dir = tmp();
  let clock = D('2026-08-01T23:59:59Z');
  const log = createLogger({ dir, compress: false, stdout: () => {}, diskFree: HEALTHY_DISK, now: () => clock });
  log('app', 'order.created', { n: 1 });
  log.flush();
  clock = D('2026-08-02T00:00:01Z');
  log('app', 'order.created', { n: 2 });
  log.flush();
  t('virada do dia: cria pasta nova', existsSync(join(dir, '2026-08-01')) && existsSync(join(dir, '2026-08-02')));
  t('virada do dia: nenhuma linha perdida', jsonl(dir, '2026-08-01').length === 1 && jsonl(dir, '2026-08-02').length === 1);
  // 23:59 UTC não pode cair na pasta do dia local
  const d1 = readFileSync(join(dir, '2026-08-01', jsonl(dir, '2026-08-01')[0]), 'utf8');
  t('virada do dia: pasta é UTC, não TZ local', JSON.parse(d1.trim()).ts.startsWith('2026-08-01'));
  rmSync(dir, { recursive: true, force: true });
}

// ── 3. retenção: apaga o que deve, preserva o que não deve ──────────────────
{
  const dir = tmp();
  const mk = (day, files) => {
    mkdirSync(join(dir, day), { recursive: true });
    for (const f of files) writeFileSync(join(dir, day, f), 'x'.repeat(500));
  };
  const files = ['access-h-aaa111-000.jsonl', 'security-h-aaa111-000.jsonl'];
  mk('2026-08-01', files);            // hoje
  mk('2026-07-31', files);            // ontem
  mk('2026-07-29', files);            // 3 dias: access expira (2), security não (30)
  mk('2026-06-01', files);            // 61 dias: tudo expira
  mkdirSync(join(dir, '2026-07-29-evil'), { recursive: true });
  writeFileSync(join(dir, '2026-07-28'), 'arquivo, nao diretorio');

  const now = () => D('2026-08-01T12:00:00Z');
  const res = sweep({ dir, now });

  t('retenção: preserva HOJE integralmente', jsonl(dir, '2026-08-01').length === 2);
  t('retenção: preserva ONTEM integralmente', jsonl(dir, '2026-07-31').length === 2);
  t('retenção: apaga access expirado (2d)', !existsSync(join(dir, '2026-07-29', files[0])));
  t('retenção: PRESERVA security no mesmo dia (30d)', existsSync(join(dir, '2026-07-29', files[1])));
  t('retenção: remove pasta cujo último arquivo expirou', !existsSync(join(dir, '2026-06-01')));
  t('retenção: registra bytes liberados', res.bytesFreed >= 1500, `bytes=${res.bytesFreed}`);
  t('guarda 1: ignora dir que não casa a data exata', existsSync(join(dir, '2026-07-29-evil')));
  t('guarda 1: ignora entrada que não é diretório', existsSync(join(dir, '2026-07-28')));
  rmSync(dir, { recursive: true, force: true });
}

// ── 3b. piso rígido resiste a config inválida ───────────────────────────────
{
  const dir = tmp();
  for (const day of ['2026-08-01', '2026-07-31', '2026-07-30']) {
    mkdirSync(join(dir, day), { recursive: true });
    writeFileSync(join(dir, day, 'access-h-aaa111-000.jsonl'), 'x');
  }
  const now = () => D('2026-08-01T12:00:00Z');
  sweep({ dir, retention: { default: 0, access: 0 }, now });
  t('piso: retenção 0 NÃO apaga hoje', existsSync(join(dir, '2026-08-01')));
  t('piso: retenção 0 NÃO apaga ontem', existsSync(join(dir, '2026-07-31')));
  t('piso: retenção 0 apaga o que é mais velho que ontem', !existsSync(join(dir, '2026-07-30')));
  rmSync(dir, { recursive: true, force: true });
}

// ── 3c. guarda de symlink ───────────────────────────────────────────────────
{
  const dir = tmp();
  const outside = tmp();
  writeFileSync(join(outside, 'precioso.txt'), 'nao pode sumir');
  let made = false;
  try { symlinkSync(outside, join(dir, '2026-06-01'), 'dir'); made = true; } catch { /* sem privilégio no Windows */ }
  if (made) {
    sweep({ dir, now: () => D('2026-08-01T12:00:00Z') });
    t('guarda 3: symlink não é seguido nem apagado através', existsSync(join(outside, 'precioso.txt')));
  } else {
    console.log('  SKIP- guarda de symlink (sem privilégio pra criar symlink)');
  }
  rmSync(dir, { recursive: true, force: true });
  rmSync(outside, { recursive: true, force: true });
}

// ── 4. isolamento entre processos ───────────────────────────────────────────
{
  const dir = tmp();
  const child = join(dir, 'child.mjs');
  writeFileSync(child, `
import { createLogger } from ${JSON.stringify(pathToFileURL(LOGGER).href)};
const log = createLogger({ dir: ${JSON.stringify(dir)}, compress: false, stdout: () => {}, diskFree: () => ({ free: 64 * 1024 ** 3, total: 512 * 1024 ** 3 }), now: () => new Date('2026-08-01T10:00:00Z') });
for (let i = 0; i < 200; i++) log('access', 'e', { i, pid: process.pid });
log.flush();
`);
  execFileSync(process.execPath, [child], { stdio: 'ignore' });
  execFileSync(process.execPath, [child], { stdio: 'ignore' });
  const files = jsonl(dir, '2026-08-01');
  const boots = new Set(files.map((f) => f.split('-')[2]));
  t('isolamento: cada processo escreve no seu arquivo', boots.size === 2, `boots=${[...boots].join(',')}`);
  let corrupt = 0, lines = 0;
  for (const f of files) {
    for (const l of readFileSync(join(dir, '2026-08-01', f), 'utf8').trim().split('\n')) {
      lines++;
      try { JSON.parse(l); } catch { corrupt++; }
    }
  }
  t('isolamento: zero linha corrompida', corrupt === 0 && lines === 400, `linhas=${lines} corrompidas=${corrupt}`);
  rmSync(dir, { recursive: true, force: true });
}

// ── 5. ausência de dado sensível nos arquivos ───────────────────────────────
{
  const dir = tmp();
  const KEY = 'chave-de-teste-nao-e-segredo-real';
  const ALLOW = new Set(['path', 'status', 'method', 'actor', 'ip_hash', 'ip_net', 'body_bytes', 'req_id']);
  const redact = (f) => Object.fromEntries(Object.entries(f).filter(([k]) => ALLOW.has(k)));

  const log = createLogger({ dir, compress: false, redact, stdout: () => {}, diskFree: HEALTHY_DISK, now: () => D('2026-08-01T10:00:00Z') });

  // Fluxo real: request autenticada com header, body, cookie, CPF e cartão.
  const CPF = '529.982.247-25', CARD = '4111111111111111';
  const TOKEN = 'eyJhbGciOiJIUzI1NiJ9.QUJDREVGRw.c2lnbmF0dXJl';
  log('access', 'http.request.completed', {
    method: 'POST', path: '/v1/checkout', status: 201,
    authorization: `Bearer ${TOKEN}`,
    cookie: 'session=abc123def456',
    body: { cpf: CPF, card: CARD, nome: 'Fulano de Tal' },
    query: `?cpf=${CPF}&token=${TOKEN}`,
    actor: pseudonym('user-42', KEY),
    body_bytes: 318,
    ...ipFields('203.0.113.77', KEY, '2026-08-01'),
  });
  log.flush();

  const blob = jsonl(dir, '2026-08-01').map((f) => readFileSync(join(dir, '2026-08-01', f), 'utf8')).join('');
  const leaks = [
    ['CPF', CPF], ['CPF sem máscara', '52998224725'], ['cartão', CARD], ['token', TOKEN],
    ['cookie de sessão', 'session=abc123'], ['header Authorization', 'Bearer '],
    ['nome do titular', 'Fulano'], ['IP bruto', '203.0.113.77'],
  ];
  for (const [label, pat] of leaks) t(`sem dado sensível: ${label} não aparece no arquivo`, !blob.includes(pat));
  const rec = JSON.parse(blob.trim().split('\n')[0]);
  t('correlação preservada: pseudônimo do ator presente', /^u_[0-9a-f]{16}$/.test(rec.actor));
  t('correlação preservada: ip_hash presente', /^ip_[0-9a-f]{16}$/.test(rec.ip_hash));
  t('correlação preservada: rede grosseira /24', rec.ip_net === '203.0.113.0/24');
  t('metadado no lugar do valor: tamanho do body', rec.body_bytes === 318);
  rmSync(dir, { recursive: true, force: true });
}

// ── 5b. pseudônimo não degrada pra hash puro ────────────────────────────────
{
  let threw = false;
  try { pseudonym('x', ''); } catch { threw = true; }
  t('pseudônimo: recusa operar sem chave (HMAC, não hash puro)', threw);
  t('pseudônimo: estável pro mesmo valor', pseudonym('a', 'k') === pseudonym('a', 'k'));
  t('pseudônimo: difere entre valores', pseudonym('a', 'k') !== pseudonym('b', 'k'));
  t('pseudônimo: salt diferente quebra ligação entre dias', pseudonym('a', 'k1') !== pseudonym('a', 'k2'));
  t('ipNet: IPv6 vira /48', ipNet('2001:db8:abcd:1234::1') === '2001:db8:abcd::/48');
}

// ── 6. disco cheio: desliga arquivo, mantém stdout, não derruba ─────────────
{
  const dir = tmp();
  const out = [];
  const log = createLogger({
    dir, compress: false, stdout: (l) => out.push(l), now: () => D('2026-08-01T10:00:00Z'),
    diskFree: () => ({ free: 1024, total: 100 * 1024 * 1024 * 1024 }),
  });
  let threw = false;
  try { log('access', 'e', { i: 1 }); log.flush(); log('access', 'e', { i: 2 }); log.flush(); }
  catch { threw = true; }
  t('disco cheio: não lança, app não cai', !threw);
  t('disco cheio: sink de arquivo desligado', log.stats().fileSink === false);
  t('disco cheio: nada escrito em disco', !existsSync(join(dir, '2026-08-01')) || jsonl(dir, '2026-08-01').length === 0);
  t('disco cheio: stdout continua recebendo', out.filter((l) => l.includes('"event":"e"')).length === 2);
  t('disco cheio: grita uma vez sobre o sink desligado', out.filter((l) => l.includes('log.file_sink.disabled')).length === 1);
  t('disco cheio: conta o que descartou', log.stats().dropped > 0);
  rmSync(dir, { recursive: true, force: true });
}

// ── 7. retenção por stream vem de env, com global de fallback ───────────────
{
  const r = retentionFromEnv({});
  t('retenção default: security(30) > error(14) > app(3) > access(2)', r.security === 30 && r.error === 14 && r.app === 3 && r.access === 2);
  const g = retentionFromEnv({ LOG_RETENTION_DAYS: '5' });
  t('retenção: global sobrescreve todos os streams', g.access === 5 && g.security === 5);
  const p = retentionFromEnv({ LOG_RETENTION_DAYS: '5', LOG_RETENTION_SECURITY_DAYS: '90' });
  t('retenção: por-stream vence o global', p.access === 5 && p.security === 90);
  t('streamOf: job.<tipo> é reconhecido', streamOf('job.queue-h-aaa111-000.jsonl') === 'job.queue');
}

console.log(`\n${ok} ok, ${fail} fail`);
process.exit(fail === 0 ? 0 : 1);
