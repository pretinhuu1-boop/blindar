// Integridade do registro de pares — barato, e roda em segundos.
//
// O gate de verdade (scripts/check-selftest.sh) leva ~25 minutos porque executa
// cada check duas vezes. Este arquivo não executa nada: só confere que o
// REGISTRO é coerente. Serve para pegar em 2 segundos o que hoje só apareceria
// depois de meia hora, ou pior, não apareceria.
//
// Cada asserção aqui existe por causa de algo que aconteceu:
//
//  1. fixture referenciado que não existe — apaguei `project-deps-*` achando que
//     era meu, e era do check-deps-sync. O gate imprimia SKIP e seguia verde: a
//     cobertura caía e ninguém era avisado.
//  2. check registrado que não existe — par sobrevive a um rename do check e
//     vira SKIP permanente.
//  3. par duplicado — o mesmo check contado duas vezes no numerador inflava a
//     cobertura, que foi como ela chegou a 101%.
//  4. fixture órfão — diretório em tests/fixtures/ que nenhum par usa. Não
//     quebra nada, mas é onde mora fixture que alguém escreveu e esqueceu de
//     registrar, e um check que parecia coberto e não está.

import { readFileSync, existsSync, readdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const raiz = join(dirname(fileURLToPath(import.meta.url)), '..');
const selftest = readFileSync(join(raiz, 'scripts', 'check-selftest.sh'), 'utf8');

const pares = [];
for (const linha of selftest.split('\n')) {
  const m = linha.match(/^\s*"(check-[a-z0-9.-]+\.sh)\s*\|\s*([a-z0-9-]+)\s*\|\s*([a-z0-9-]+)"/);
  if (m) pares.push({ check: m[1], vuln: m[2], limpo: m[3] });
}

const falhas = [];
const usados = new Set();

if (pares.length < 50) falhas.push(`só ${pares.length} pares lidos — o parser do registro quebrou?`);

const vistos = new Set();
for (const p of pares) {
  if (vistos.has(p.check)) falhas.push(`${p.check}: registrado duas vezes (infla o numerador)`);
  vistos.add(p.check);

  if (!existsSync(join(raiz, 'templates', 'checks', p.check))) {
    falhas.push(`${p.check}: par registrado para check que não existe`);
  }
  for (const fx of [p.vuln, p.limpo]) {
    usados.add(fx);
    if (!existsSync(join(raiz, 'tests', 'fixtures', fx))) {
      falhas.push(`${p.check}: fixture ${fx} não existe`);
    }
  }
  if (p.vuln === p.limpo) {
    falhas.push(`${p.check}: fixture vulnerável e limpo são o mesmo (${p.vuln}) — não há contrato`);
  }
}

// Órfãos são AVISO, não falha: nem todo diretório em fixtures/ é par de check
// (há material auxiliar, como o do attack-recon).
const orfaos = readdirSync(join(raiz, 'tests', 'fixtures'), { withFileTypes: true })
  .filter((e) => e.isDirectory() && e.name.startsWith('project-') && !usados.has(e.name))
  .map((e) => e.name);

if (falhas.length) {
  console.error(`FALHA: ${falhas.length} problema(s) no registro de pares:`);
  for (const f of falhas) console.error('  ' + f);
  process.exit(1);
}

console.log(`ok — ${pares.length} pares, todos com check e fixtures existentes`);
if (orfaos.length) {
  console.log(`  aviso: ${orfaos.length} fixture(s) project-* sem par registrado:`);
  for (const o of orfaos) console.log(`    ${o}`);
}
