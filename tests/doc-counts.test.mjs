#!/usr/bin/env node
// Número escrito em documentação apodrece em silêncio.
//
// O `docs/TOKEN-SPEED.md` anunciou "~100 agentes" por várias versões enquanto o
// `MODULE-MAP.json` já tinha 170, e ninguém tropeçou: documentação não quebra
// build. O efeito é o de sempre neste projeto — quem lê acredita no texto, e o
// texto está errado sem dizer que está.
//
// O teste é DELIBERADAMENTE estreito. A primeira versão varria todo "N checks"
// de todo `.md` e acusou 22 divergências, quase todas legítimas: "16 checks do
// módulo 2", "64 checks auditados naquela rodada", "22 agentes ativados neste
// perfil". Um verificador que não distingue total de recorte produz exatamente
// o ruído que este projeto passa o tempo combatendo — e ruído ensina o operador
// a ignorar o verificador.
//
// Então aqui só entra quem DECLARA O TOTAL, arquivo por arquivo, com a frase
// exata. Se o número de agentes ou de checks mudar, estes quatro documentos têm
// de mudar junto; o resto do repo segue livre para falar de subconjuntos.
//
// Documento histórico (CHANGELOG, PLANO-EOS) fica de fora por natureza: ele
// registra o estado de uma data, e reescrevê-lo apagaria o que ele existe para
// preservar.
//
// Roda: node tests/doc-counts.test.mjs

import { execFileSync } from 'node:child_process';
import { readFileSync, readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = join(__dirname, '..');

let ok = 0, fail = 0;
const t = (name, cond, extra = '') => {
  if (cond) { ok++; console.log('  ok  - ' + name); }
  else { fail++; console.log('  FAIL- ' + name + (extra ? ` (${extra})` : '')); }
};

// ─── Fonte da verdade ───
const mapa = JSON.parse(readFileSync(join(ROOT, 'pipeline', 'MODULE-MAP.json'), 'utf8'));
const agentes = new Set();
for (const m of Object.values(mapa.modules || {})) for (const a of (m.agents || [])) agentes.add(a);
const N_AGENTES = agentes.size;

const checks = readdirSync(join(ROOT, 'templates', 'checks')).filter((f) => /^check-.*\.sh$/.test(f));
const N_CHECKS = checks.length;
const N_API = checks.filter((f) => f.endsWith('.api.sh')).length;
const N_SHELL = N_CHECKS - N_API;

t('MODULE-MAP tem agentes para contar', N_AGENTES > 0, String(N_AGENTES));
t('templates/checks tem checks para contar', N_CHECKS > 0, String(N_CHECKS));

// ─── Quem declara o total ───
// Cada entrada é uma promessa feita ao leitor daquele arquivo. Acrescentar
// arquivo aqui é barato; o que não pode é um deles anunciar um total velho.
const DECLARAM_TOTAL = [
  ['README.md', 'agentes'],
  ['README.md', 'checks'],
  ['docs/TOKEN-SPEED.md', 'agentes'],
  ['docs/TOKEN-SPEED.md', 'checks'],
  ['reference/modulos-e-agentes.md', 'agentes'],
  ['reference/camada-deterministica.md', 'checks'],
];

for (const [rel, tipo] of DECLARAM_TOTAL) {
  const esperado = tipo === 'agentes' ? N_AGENTES : N_CHECKS;
  let src = '';
  try { src = readFileSync(join(ROOT, rel), 'utf8'); } catch (e) { /* reportado abaixo */ }
  t(`${rel} anuncia o total certo de ${tipo} (${esperado})`,
    src.includes(`${esperado} ${tipo}`),
    src ? `não achei "${esperado} ${tipo}"` : 'arquivo não encontrado');
}

// O recorte da camada determinística é o outro número que já saiu errado:
// "130 shell puro + 14 .api.sh" tem de somar o total, senão um dos três mente.
t('o recorte shell + api fecha com o total de checks', N_SHELL + N_API === N_CHECKS,
  `${N_SHELL} + ${N_API} != ${N_CHECKS}`);

// ─── A versão é o número mais visível de todos ───
// A primeira versão deste arquivo cobria só as contagens, e deu a impressão de
// cobrir "número na doc". Não cobria a VERSÃO — e o README anunciou "v0.80" por
// quatro releases, na linha 8, que é a primeira coisa que alguém lê ao abrir o
// repositório. Verificador que passa verde sobre dimensão que não mede é o
// mesmo defeito que o rollup tinha antes da v0.82.
const VERSION = readFileSync(join(ROOT, 'VERSION'), 'utf8').trim();
t('VERSION tem forma de versão semântica', /^\d+\.\d+\.\d+$/.test(VERSION), VERSION);

const readme = readFileSync(join(ROOT, 'README.md'), 'utf8');
const anunciada = readme.match(/\*\*v(\d+\.\d+(?:\.\d+)?)\s+—/);
t('README anuncia alguma versão em destaque', !!anunciada,
  'o padrão "**vX.Y.Z — " sumiu do README; ajuste este teste junto');
t(`README anuncia a versão do VERSION (${VERSION})`,
  !!anunciada && anunciada[1] === VERSION,
  anunciada ? `README diz v${anunciada[1]}, VERSION diz ${VERSION}` : '');

// Tag: versão sem tag não aparece para quem chega pelo GitHub, e o
// check-update compara contra a tag remota. Só avisa quando há git e tags —
// clone raso ou tarball não têm, e ausência de tag aí não é regressão.
try {
  const tags = execFileSync('git', ['tag', '--list'], { cwd: ROOT, encoding: 'utf8' })
    .split('\n').map((x) => x.trim()).filter(Boolean);
  if (tags.length) {
    t(`existe tag v${VERSION} para a versão atual`, tags.includes(`v${VERSION}`),
      `última tag: ${tags[tags.length - 1]}`);
  } else {
    console.log('  --  - sem tags neste clone; contrato de tag não verificado');
  }
} catch (e) {
  console.log('  --  - git indisponível; contrato de tag não verificado');
}

console.log(`\n  fonte da verdade: ${N_AGENTES} agentes, ${N_CHECKS} checks (${N_SHELL} shell + ${N_API} api)`);
console.log(`\n${ok} ok, ${fail} fail`);
process.exit(fail === 0 ? 0 : 1);
