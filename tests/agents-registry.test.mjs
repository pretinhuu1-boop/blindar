#!/usr/bin/env node
// Registro de agentes: frontmatter completo, lead/authority válidos, e
// coerência nos DOIS sentidos com o pipeline/MODULE-MAP.json.
//
// Existe porque metadata que ninguém valida apodrece em silêncio. Antes deste
// teste o repo tinha, sem que nada acusasse: 2 agentes sem frontmatter nenhum,
// e 2 playbooks (infra-runtime, race-fuzzing) que nenhum módulo ativava — ou
// seja, escritos, mantidos e nunca executados.
//
// Roda: node tests/agents-registry.test.mjs

import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = join(__dirname, '..');
const AGENTS = join(ROOT, 'agents');
const CHECKS = join(ROOT, 'templates', 'checks');

let ok = 0, fail = 0;
const t = (name, cond, extra = '') => {
  if (cond) { ok++; console.log('  ok  - ' + name); }
  else { fail++; console.log('  FAIL- ' + name + (extra ? ` (${extra})` : '')); }
};

const LEADS = new Set([
  'chief-architect', 'security-lead', 'data-lead', 'platform-lead', 'sre-lead',
  'runtime-lead', 'privacy-lead', 'ai-lead', 'qa-lead', 'frontend-lead',
  'release-lead', 'product-lead',
]);
// Autoridade = o que o agente pode FAZER. 'gate' bloqueia entrega e NÃO edita:
// somar autoridade de decisão à de execução é como decisão ruim vira fato
// consumado antes de ser revista.
const AUTHORITIES = new Set(['read-only', 'plan', 'implement', 'validate', 'adversary', 'gate']);

// 'module' aceita as duas formas, porque as duas são legítimas: a maioria dos
// agentes pertence a um módulo (`module: 7`), e alguns pertencem a mais de um
// de verdade — o db-architect entra no 7 (banco) e no 9 (performance de query),
// e declara `modules: [7, 9]`. Exigir só a forma singular reprovaria um
// frontmatter correto.
const REQUIRED = ['name', 'category', 'priority', 'lead', 'authority', 'description'];

const files = readdirSync(AGENTS).filter((f) => f.endsWith('.md'));
const parsed = new Map();

// ── 1. frontmatter completo e coerente ──────────────────────────────────────
const semFrontmatter = [];
const camposFaltando = [];
const nomeDivergente = [];
const leadInvalido = [];
const authInvalida = [];
const moduloInvalido = [];

for (const f of files) {
  const name = f.replace(/\.md$/, '');
  const src = readFileSync(join(AGENTS, f), 'utf8').replace(/\r\n/g, '\n');
  const m = src.match(/^---\n([\s\S]*?)\n---/);
  if (!m) { semFrontmatter.push(f); continue; }

  const fm = m[1];
  const get = (k) => (fm.match(new RegExp(`^${k}:[ \\t]*(.*)$`, 'm')) || [])[1]?.trim();
  const faltando = REQUIRED.filter((k) => !new RegExp(`^${k}:`, 'm').test(fm));
  if (faltando.length) camposFaltando.push(`${f}: ${faltando.join(',')}`);

  const declarado = get('name');
  if (declarado && declarado !== name) nomeDivergente.push(`${f} declara "${declarado}"`);

  const lead = get('lead');
  if (lead && !LEADS.has(lead)) leadInvalido.push(`${f}: ${lead}`);

  const auth = get('authority');
  if (auth && !AUTHORITIES.has(auth)) authInvalida.push(`${f}: ${auth}`);

  const raw = get('module') ?? get('modules');
  const mods = raw === undefined
    ? []
    : String(raw).replace(/[[\]]/g, '').split(',').map((x) => Number(x.trim())).filter((x) => !Number.isNaN(x));
  if (mods.length === 0 || mods.some((x) => !Number.isInteger(x) || x < 1 || x > 19)) {
    moduloInvalido.push(`${f}: ${raw ?? '(ausente)'}`);
  }

  parsed.set(name, { lead, auth, mods });
}

t('todo agente tem frontmatter', semFrontmatter.length === 0, semFrontmatter.join(' '));
t('todo agente declara os campos obrigatórios', camposFaltando.length === 0, camposFaltando.join(' | '));
t('name do frontmatter bate com o nome do arquivo', nomeDivergente.length === 0, nomeDivergente.join(' | '));
t('todo lead é um lead conhecido', leadInvalido.length === 0, leadInvalido.join(' | '));
t('toda authority é válida', authInvalida.length === 0, authInvalida.join(' | '));
t('todo agente declara module/modules em 1..19', moduloInvalido.length === 0, moduloInvalido.join(' | '));

// ── 2. coerência com o MODULE-MAP, nos dois sentidos ────────────────────────
const map = JSON.parse(readFileSync(join(ROOT, 'pipeline', 'MODULE-MAP.json'), 'utf8'));
const noMapa = [...new Set(Object.values(map.modules).flatMap((m) => m.agents))];

// Ida: toda entrada do mapa precisa existir como playbook OU como check.
// Nem toda entrada tem .md — checks determinísticos puros (trivy, osv-scanner,
// entrypoint-cmd...) são unidades executáveis sem playbook, e isso é legítimo.
const naoResolve = noMapa.filter(
  (a) => !existsSync(join(AGENTS, `${a}.md`)) && !existsSync(join(CHECKS, `check-${a}.sh`)),
);
t('toda entrada do MODULE-MAP resolve para playbook ou check', naoResolve.length === 0, naoResolve.join(' '));

// Volta: todo playbook precisa ser ativado por algum módulo. Playbook que
// nenhum módulo referencia nunca roda — é custo de manutenção sem cobertura.
const orfaos = [...parsed.keys()].filter((a) => !noMapa.includes(a));
t('todo playbook é ativado por algum módulo', orfaos.length === 0, orfaos.join(' '));

// ── 3. o módulo declarado no agente existe no mapa ──────────────────────────
const moduloInexistente = [...parsed.entries()]
  .flatMap(([k, v]) => v.mods.filter((m) => !map.modules[String(m)]).map((m) => `${k}→m${m}`));
t('module declarado pelo agente existe no MODULE-MAP', moduloInexistente.length === 0, moduloInexistente.join(' '));

// ── 4. todo lead tem pelo menos um agente ───────────────────────────────────
const leadsUsados = new Set([...parsed.values()].map((v) => v.lead).filter(Boolean));
const leadsVazios = [...LEADS].filter((l) => !leadsUsados.has(l));
t('todo lead conhecido governa ao menos um agente', leadsVazios.length === 0, leadsVazios.join(' '));

// ── 5. autoridade 'gate' não pode ser a maioria ─────────────────────────────
// Se quase todo agente pode bloquear, ninguém bloqueia de fato — o gate perde
// significado e vira ruído no relatório.
const gates = [...parsed.values()].filter((v) => v.auth === 'gate').length;
t('autoridade gate é exceção, não regra', gates > 0 && gates <= Math.ceil(files.length * 0.1), `${gates}/${files.length}`);

console.log('');
console.log(`  ${files.length} agentes · ${LEADS.size} leads · ${noMapa.length} entradas no mapa`);
console.log(`${ok} ok, ${fail} fail`);
process.exit(fail > 0 ? 1 : 0);
