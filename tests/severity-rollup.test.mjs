#!/usr/bin/env node
// O agregado tem que carregar severidade — e o scanner não pode acusar a si mesmo.
//
// Três defeitos medidos em campo (FastList, set/2026, blindar 0.80) que este
// teste existe para não deixar voltar:
//
// 1. O `run-report.json` tinha passed/failed/skipped/deferred e coverage_pct, e
//    nada de `crit`/`high`. As entradas de results[] traziam `findings` como
//    número puro. Quem agregava o rollup para dar veredito lia 0 crítico
//    enquanto os check-*.json guardavam 4 crit do semgrep e 206 high do
//    mock-killer. Verde por omissão — o modo de falha que este projeto recusa.
//
// 2. O semgrep varria o `.blindar/` e reportava como crit os certificados de
//    teste que o próprio blindar gera ali. Crit auto-infligido é
//    indistinguível de segredo real até alguém abrir o caminho.
//
// 3. Matcher de texto casava linha de COMENTÁRIO e dava crit/high por ela — o
//    que ainda punia documentar a decisão, porque apagar o comentário fazia o
//    achado sumir.
//
// Roda: node tests/severity-rollup.test.mjs

import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync, writeFileSync, mkdirSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = join(__dirname, '..');
const CHECKS = join(ROOT, 'templates', 'checks');
const LIB = join(CHECKS, '_lib.sh');

let ok = 0, fail = 0;
const t = (name, cond, extra = '') => {
  if (cond) { ok++; console.log('  ok  - ' + name); }
  else { fail++; console.log('  FAIL- ' + name + (extra ? ` (${extra})` : '')); }
};

const sh = (script, cwd) =>
  execFileSync('bash', ['-c', script], { cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });

const q = (p) => JSON.stringify(p);
const work = mkdtempSync(join(tmpdir(), 'blindar-sevrollup-'));
const readResult = (base, agent) =>
  JSON.parse(readFileSync(join(base, '.blindar', 'results', agent + '.json'), 'utf8'));

// ─── 1. emit_result grava severities ───
sh([
  'source ' + q(LIB),
  'add_finding crit "chave" a.js 1',
  'add_finding high "outra" b.js 2',
  'add_finding high "mais uma" c.js 3',
  'add_finding low  "nota" d.js 4',
  'emit_result check-teste failed 1 >/dev/null 2>&1',
].join('\n'), work);

const res = readResult(work, 'check-teste');
t('check-result traz o bloco severities', !!res.severities, JSON.stringify(res.severities));
t('severities conta crit/high/low corretamente',
  res.severities && res.severities.crit === 1 && res.severities.high === 2 && res.severities.low === 1,
  JSON.stringify(res.severities));
t('findings_count segue coerente com a lista', res.findings_count === res.findings.length);

// ─── 2. schema exige os campos (senão somem sem ninguém notar) ───
const schemaCheck = JSON.parse(readFileSync(join(ROOT, 'schemas', 'check-result.schema.json'), 'utf8'));
t('check-result.schema exige severities', (schemaCheck.required || []).includes('severities'));
const schemaRun = JSON.parse(readFileSync(join(ROOT, 'schemas', 'run-report.schema.json'), 'utf8'));
t('run-report.schema exige severity_totals', (schemaRun.required || []).includes('severity_totals'));

// ─── 3. o orquestrador soma e publica ───
// Não por grep no fonte: o orquestrador roda de verdade num projeto de
// mentira, e o teste lê o artefato que o consumidor leria. Fixture prova a
// unidade; só a execução real prova o sistema — foi um rollup verde sobre 130
// results contraditórios que trouxe este arquivo à existência.
const alvo = join(work, 'alvo');
mkdirSync(join(alvo, 'src'), { recursive: true });
writeFileSync(join(alvo, 'src', 'a.ts'), "export const f = () => { console.log('aqui'); };\n");
sh('bash ' + q(join(ROOT, 'scripts', 'blindar-run.sh')) + ' --only mock-killer,homolog-only >/dev/null 2>&1 || true', alvo);

const rollup = JSON.parse(readFileSync(join(alvo, '.blindar', 'run-report.json'), 'utf8'));
t('run-report traz severity_totals no topo', !!rollup.severity_totals, JSON.stringify(rollup.severity_totals));
t('severity_totals soma o high que o check achou',
  rollup.severity_totals && rollup.severity_totals.high >= 1, JSON.stringify(rollup.severity_totals));
t('cada results[] carrega severities',
  rollup.results.every((r) => r.severities && typeof r.severities.crit === 'number'));
t('o rollup produzido valida contra o schema',
  sh('node ' + q(join(ROOT, 'scripts', 'validate-schemas.js')) + ' --input .blindar/run-report.json', alvo)
    .includes('Schemas válidos'));

const progresso = readFileSync(join(alvo, '.blindar', 'progress.jsonl'), 'utf8')
  .trim().split('\n').filter(Boolean).map((l) => JSON.parse(l));
t('progress.jsonl tem uma linha por agente concluído', progresso.length === 2, JSON.stringify(progresso));
t('cada linha de progresso nomeia agente, status e hora',
  progresso.every((p) => p.agent && p.status && p.ts));

const runner = readFileSync(join(ROOT, 'scripts', 'blindar-run.sh'), 'utf8');
t('blindar-run.sh define severities_of()', /severities_of\s*\(\)/.test(runner));
t('deferred stub também traz severities', /"deferred"[^\n]*"severities"/.test(runner));

// ─── 4. achado apontando para o workdir do próprio blindar é descartado ───
sh([
  'source ' + q(LIB),
  'add_finding crit "Private Key detected" ".blindar/tls/app.key" 1',
  'add_finding crit "Private Key detected" "./.blindar/pgtls/server.key" 1',
  'add_finding crit "segredo de verdade" "src/config.ts" 9',
  'emit_result check-selfscan failed 1 >/dev/null 2>&1',
].join('\n'), work);
const self = readResult(work, 'check-selfscan');
t('cert de teste do próprio blindar não vira crit da app', self.severities.crit === 1,
  JSON.stringify(self.findings.map((f) => f.file)));
t('achado fora do workdir continua contando',
  self.findings.length === 1 && self.findings[0].file === 'src/config.ts');

// fixture versionada (tests/fixtures/x/.blindar/...) NÃO pode ser descartada:
// ali o .blindar é insumo do teste, não workdir da rodada.
sh([
  'source ' + q(LIB),
  'add_finding high "achado em fixture" "tests/fixtures/projeto/.blindar/config.yml" 3',
  'emit_result check-fixture failed 1 >/dev/null 2>&1',
].join('\n'), work);
t('.blindar de fixture (com prefixo) segue auditável',
  readResult(work, 'check-fixture').findings.length === 1);

// ─── 5. o scanner externo exclui o workdir no próprio comando ───
const semgrep = readFileSync(join(CHECKS, 'check-semgrep.sh'), 'utf8');
t('check-semgrep exclui o workdir em toda invocação',
  (semgrep.match(/SEMGREP_EXCLUDE_ARGS\[@\]/g) || []).length >= 3,
  'nativo, fallback de ruleset e container precisam dos três');
t('trivy pula o workdir (--skip-dirs)',
  /--skip-dirs/.test(readFileSync(join(CHECKS, 'check-deps-audit.sh'), 'utf8')));

// ─── 6. comentário não é config viva ───
const linhas = [
  'a.yml:3:# NODE_ENV=development',
  'b.yml:9:  NODE_ENV: development',
  'c.js:1:// unsafe-inline foi removido',
  'd.js:2:script-src unsafe-inline # nota',
];
const filtered = sh(
  'source ' + q(LIB) + '\n' +
  'printf "%s\\n" ' + linhas.map(q).join(' ') + ' | drop_comment_lines',
  work).trim().split('\n');
t('linha que É comentário some',
  !filtered.some((l) => l.startsWith('a.yml') || l.startsWith('c.js')), filtered.join(' | '));
t('linha que TEM comentário no fim continua valendo',
  filtered.some((l) => l.startsWith('b.yml')) && filtered.some((l) => l.startsWith('d.js')),
  filtered.join(' | '));

t('check-homolog-only filtra comentário antes de dar crit',
  (readFileSync(join(CHECKS, 'check-homolog-only.sh'), 'utf8').match(/drop_comment_lines/g) || []).length >= 4);
t('check-defense-theater filtra comentário antes de dar high',
  /drop_comment_lines/.test(readFileSync(join(CHECKS, 'check-defense-theater.sh'), 'utf8')));

// ─── 7. log estruturado de backend ≠ debug esquecido ───
const proj = join(work, 'proj');
mkdirSync(join(proj, 'src'), { recursive: true });
writeFileSync(join(proj, 'src', 'wa.ts'), [
  'export function f(id: string) {',
  "  console.log('[cobranca] enviando', id);",
  "  console.log('aqui');",
  '}',
  '',
].join('\n'));
sh('BLINDAR_DIR=.blindar bash ' + q(join(CHECKS, 'check-mock-killer.sh')) + ' >/dev/null 2>&1 || true', proj);
const mk = readResult(proj, 'check-mock-killer');
t('console com prefixo de módulo vira low', mk.severities.low >= 1, JSON.stringify(mk.severities));
t('console.log solto continua high', mk.severities.high >= 1, JSON.stringify(mk.severities));

rmSync(work, { recursive: true, force: true });

console.log('\n' + ok + ' ok, ' + fail + ' fail');
process.exit(fail === 0 ? 0 : 1);
