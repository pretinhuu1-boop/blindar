#!/usr/bin/env node
// Contrato de mapeamento check → gate: nenhum check pode rodar, achar, e não
// chegar a dimensão nenhuma.
//
// Existe por um buraco medido no próprio repositório: 18 checks emitiam result
// e caíam no `*)` genérico do gate_of(). Entre eles, `check-payments` com crit
// de PCI (CVV em código, PAN em log), `check-client-bundle-secrets` com segredo
// de provider servido ao browser, `check-healthtech-fhir` com PHI em log e
// `check-git-hygiene` com `.env` fora do .gitignore. Todos rodavam. Todos
// achavam. Nenhum contava para o veredito — o relatório dizia, em voz alta,
// "não contam pro veredito", e nada acontecia por causa disso.
//
// É o mesmo defeito do "critical" fora do enum que o severity-contract pegou:
// o achado existe no JSON e nenhum consumidor o conta. A diferença é o degrau
// onde ele se perde — lá era a string da severidade, aqui é o nome do agente.
//
// O contrato tem duas metades, e a segunda é a que evita a regressão voltar
// como ruído aceito:
//   1. todo agente cai num dos 11 gates, OU
//   2. está em motivo_fora_do_gate() com um motivo ESCRITO.
// Exclusão sem motivo é silêncio, e silêncio é onde o bug mora.
//
// Roda: node tests/gate-mapping.test.mjs

import { readFileSync, readdirSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = join(__dirname, '..');
const CHECKS = join(ROOT, 'templates', 'checks');
const GATE_SCRIPT = join(CHECKS, 'check-release-gates.sh');

let ok = 0;
let fail = 0;
const t = (name, cond, extra = '') => {
  if (cond) {
    ok++;
    console.log('  ok  - ' + name);
  } else {
    fail++;
    console.log('  FAIL- ' + name + (extra ? ` (${extra})` : ''));
  }
};

console.log('# gate-mapping: todo check que emite result chega a um gate\n');

// ─── 1. Quem são os agentes ───
// A fonte é o BLINDAR_AGENT declarado no próprio check, não o nome do arquivo.
// Os wrappers .api declaram sem o sufixo (check-pentest.api.sh emite
// "check-pentest"), e medir o mapeamento pelo nome do arquivo inventa 9 buracos
// que não existem — foi como a lista de 27 apareceu antes de alguém conferir.
const arquivos = readdirSync(CHECKS).filter((f) => /^check-.*\.sh$/.test(f));
const agentes = new Map(); // agente → arquivo
const semAgente = [];

for (const f of arquivos) {
  const src = readFileSync(join(CHECKS, f), 'utf8');
  const m = src.match(/^BLINDAR_AGENT="([^"]+)"/m);
  if (m) agentes.set(m[1], f);
  else if (/^\s*emit_result\s/m.test(src)) semAgente.push(f);
}

t(`${agentes.size} checks declaram BLINDAR_AGENT`, agentes.size > 100, `achei ${agentes.size}`);
t(
  'nenhum check chama emit_result sem declarar BLINDAR_AGENT',
  semAgente.length === 0,
  semAgente.join(', '),
);

// ─── 2. O que o gate_of() responde para cada um ───
// Um processo bash só: as duas funções são extraídas do script real e
// avaliadas, para o teste não reimplementar a regra que está testando.
const bridge = `
set -u
eval "$(sed -n '/^motivo_fora_do_gate() {/,/^}$/p;/^gate_of() {/,/^}$/p' "$1")"
sed -n 's/^GATES="\\(.*\\)"$/GATES \\1/p' "$1" | head -1
while IFS= read -r a; do
  [ -z "$a" ] && continue
  printf '%s\\t%s\\t%s\\n' "$a" "$(gate_of "$a")" "$(motivo_fora_do_gate "$a")"
done
`;

let saida;
try {
  saida = execFileSync('bash', ['-c', bridge, 'bridge', GATE_SCRIPT], {
    input: [...agentes.keys()].join('\n') + '\n',
    encoding: 'utf8',
    stdio: ['pipe', 'pipe', 'pipe'],
  });
} catch (e) {
  console.log('  FAIL- bash não conseguiu avaliar gate_of()' + (e.stderr ? `: ${e.stderr}` : ''));
  process.exit(1);
}

const linhas = saida.split('\n').filter((l) => l.length > 0);
const gatesLine = linhas.find((l) => l.startsWith('GATES '));
const GATES = new Set((gatesLine || '').replace(/^GATES /, '').trim().split(/\s+/).filter(Boolean));

t('a lista GATES foi lida do script', GATES.size === 11, `achei ${GATES.size}: ${[...GATES]}`);

const veredito = new Map(); // agente → { gate, motivo }
for (const l of linhas) {
  if (l.startsWith('GATES ')) continue;
  const [agente, gate, motivo = ''] = l.split('\t');
  veredito.set(agente, { gate, motivo });
}

t(
  'gate_of respondeu para todos os agentes',
  veredito.size === agentes.size,
  `${veredito.size} de ${agentes.size}`,
);

// ─── 3. As asserções que importam ───
const unmapped = [];
const gateDesconhecido = [];
const foraSemMotivo = [];
const motivoSemFora = [];

for (const [agente, { gate, motivo }] of veredito) {
  if (gate === 'UNMAPPED') unmapped.push(`${agente} (${agentes.get(agente)})`);
  else if (gate === 'OUT_OF_GATE') {
    if (!motivo.trim()) foraSemMotivo.push(agente);
  } else if (!GATES.has(gate)) gateDesconhecido.push(`${agente} → ${gate}`);

  if (motivo.trim() && gate !== 'OUT_OF_GATE') motivoSemFora.push(`${agente} → ${gate}`);
}

t(
  'nenhum check cai em UNMAPPED — o que roda e acha chega a uma dimensão',
  unmapped.length === 0,
  unmapped.join(', '),
);
t(
  'todo check fora do veredito tem motivo escrito em motivo_fora_do_gate()',
  foraSemMotivo.length === 0,
  foraSemMotivo.join(', '),
);
t(
  'nenhum gate_of() devolve nome de gate que não existe na lista GATES',
  gateDesconhecido.length === 0,
  gateDesconhecido.join(', '),
);
t(
  'motivo escrito implica OUT_OF_GATE (a exceção não fica meio dentro do gate)',
  motivoSemFora.length === 0,
  motivoSemFora.join(', '),
);

// ─── 4. A exceção não pode virar depósito ───
// Um `motivo_fora_do_gate()` que cresce sem limite é o balde de novo, só que com
// legenda. O número não é sagrado; o que este teste quer é que aumentá-lo seja
// uma decisão consciente, com diff, e não um efeito colateral de "esse check é
// chatinho de mapear".
const fora = [...veredito].filter(([, v]) => v.gate === 'OUT_OF_GATE').map(([a]) => a);
t(
  `no máximo 10 checks fora do veredito por desenho (hoje: ${fora.length})`,
  fora.length <= 10,
  fora.join(', '),
);

// ─── 5. Distribuição, para o buraco novo aparecer como número ───
const porGate = {};
for (const [, { gate }] of veredito) porGate[gate] = (porGate[gate] || 0) + 1;
console.log('\n# distribuição');
for (const g of [...GATES, 'OUT_OF_GATE', 'UNMAPPED']) {
  if (porGate[g]) console.log(`  ${String(porGate[g]).padStart(3)}  ${g}`);
}
console.log('\n# fora do veredito por desenho');
for (const a of fora.sort()) console.log(`  ${a.padEnd(30)} ${veredito.get(a).motivo}`);

console.log(`\n# ${ok} ok, ${fail} fail`);
process.exit(fail === 0 ? 0 : 1);
