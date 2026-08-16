#!/usr/bin/env node
// Contrato de severidade: nenhum check pode emitir valor fora do enum.
//
// Existe por um bug encontrado rodando o blindar contra um projeto real:
// check-healthtech-fhir e check-govtech-acessibilidade emitiam "critical", e
// check-ecom-checkout-conversion e check-fintech-banking-br emitiam "medium".
//
// O efeito não é cosmético. Todo consumidor casa a string EXATA:
//   check-termination   → jq '.findings_by_severity.crit'
//   check-release-gates → select(.severity=="crit")
//   check-evidence      → f.severity === "crit"
// Logo, um achado "critical" existe no JSON, não é contado por ninguém, e o
// portão de release diz GO com um crítico aberto — em FHIR (dado de paciente) e
// em acessibilidade govtech, que é obrigação legal.
//
// A guarda em tempo de execução vive no normalize_severity() do _lib.sh. Este
// teste é a rede de baixo: pega o call site errado antes de mergear, para o
// operador não depender da normalização silenciosa.
//
// Roda: node tests/severity-contract.test.mjs

import { readFileSync, readdirSync } from 'node:fs';
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

const VALIDAS = new Set(['crit', 'high', 'med', 'low']);

const arquivos = readdirSync(CHECKS).filter((f) => f.endsWith('.sh'));
const ofensores = [];

for (const f of arquivos) {
  const src = readFileSync(join(CHECKS, f), 'utf8');
  // Só literais. Chamada com variável (add_finding "$sev") é responsabilidade
  // do normalize_severity em runtime — um grep não resolve o valor dela.
  for (const m of src.matchAll(/add_finding\s+"([a-z]+)"/g)) {
    if (!VALIDAS.has(m[1])) ofensores.push(`${f}: "${m[1]}"`);
  }
}

t('nenhum check emite severidade fora de crit|high|med|low',
  ofensores.length === 0, ofensores.join(' | '));

// A guarda de runtime precisa existir e cobrir os apelidos conhecidos.
const lib = readFileSync(join(CHECKS, '_lib.sh'), 'utf8');
t('_lib.sh define normalize_severity', /normalize_severity\s*\(\)/.test(lib));
t('normalize_severity mapeia critical→crit', /critical\)\s*echo "crit"/.test(lib));
t('normalize_severity mapeia medium→med', /medium[^)]*\)\s*echo "med"/.test(lib));

// O default do desconhecido não pode ser o valor benigno. Se um valor novo
// aparecer, ele tem que APARECER — coagir para "low" o esconderia justamente
// quando ninguém sabe o que é.
const catchAll = lib.match(/\*\)\s*echo "(crit|high|med|low)"\s*;;/);
t('severidade desconhecida não vira low/med (default do desconhecido não é benigno)',
  !!catchAll && (catchAll[1] === 'high' || catchAll[1] === 'crit'),
  catchAll ? `default = ${catchAll[1]}` : 'sem catch-all');

// O schema é a fonte da verdade do enum — se ele mudar, este teste tem que saber.
const schema = JSON.parse(readFileSync(join(ROOT, 'schemas', 'check-result.schema.json'), 'utf8'));
const doSchema = schema?.properties?.findings?.items?.properties?.severity?.enum;
t('enum deste teste bate com o schema check-result',
  Array.isArray(doSchema) && doSchema.length === VALIDAS.size && doSchema.every((s) => VALIDAS.has(s)),
  JSON.stringify(doSchema));

console.log('');
console.log(`  ${arquivos.length} checks varridos`);
console.log(`${ok} ok, ${fail} fail`);
process.exit(fail > 0 ? 1 : 0);
