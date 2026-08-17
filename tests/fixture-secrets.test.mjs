// Fixture não pode carregar credencial com forma de PROVEDOR.
//
// Aconteceu TRÊS vezes nesta base, sempre igual: escrevo um segredo realista
// num fixture vulnerável, o gitleaks detecta — que é o ponto —, e o Push
// Protection do GitHub recusa o push. O trabalho já está commitado, então some
// meia hora entre descobrir e conseguir publicar.
//
// A tensão é real e não some: o fixture PRECISA de um segredo que o scanner
// detecte, senão ele não prova nada. Foi exatamente por ser mascarado demais
// que o `project-with-secrets` deixou um falso negativo do check-secrets viver
// por meses.
//
// A saída é escolher a categoria certa. O Push Protection bloqueia credencial
// de PROVEDOR — Stripe, AWS, GitHub, Slack, Google — porque essas podem ser
// revogadas e valem dinheiro. Segredo genérico ele não bloqueia:
//
//   - JWT de exemplo público do jwt.io          → gitleaks detecta, GitHub aceita
//   - `api_key_a1b2c3...`                       → idem
//   - chave privada de teste gerada na hora     → idem
//
// Este teste roda em 2 segundos e evita o ciclo commit → push recusado →
// corrigir → amend.

import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const raiz = join(dirname(fileURLToPath(import.meta.url)), '..');
const fixtures = join(raiz, 'tests', 'fixtures');

// Formas que o GitHub Push Protection reconhece e bloqueia. A lista é curta de
// propósito: são as que já custaram push recusado aqui, mais as vizinhas
// óbvias. Não tenta ser um scanner — para isso existe o gitleaks.
const PROVEDORES = [
  { nome: 'Stripe',        re: /\bsk_live_[A-Za-z0-9]{16,}/ },
  { nome: 'Stripe (test)', re: /\bsk_test_[A-Za-z0-9]{24,}/ },
  { nome: 'AWS',           re: /\bAKIA[0-9A-Z]{16}\b/ },
  { nome: 'GitHub PAT',    re: /\bgh[pousr]_[A-Za-z0-9]{36,}/ },
  { nome: 'Slack',         re: /\bxox[baprs]-[A-Za-z0-9-]{10,}/ },
  { nome: 'Google API',    re: /\bAIza[0-9A-Za-z_-]{35}\b/ },
  { nome: 'OpenAI',        re: /\bsk-[A-Za-z0-9]{32,}/ },
  { nome: 'SendGrid',      re: /\bSG\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}/ },
];

function* arquivos(dir) {
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    const p = join(dir, e.name);
    if (e.isDirectory()) { yield* arquivos(p); continue; }
    if (statSync(p).size > 512 * 1024) continue;
    yield p;
  }
}

const achados = [];
for (const arq of arquivos(fixtures)) {
  let texto;
  try { texto = readFileSync(arq, 'utf8'); } catch { continue; }
  texto.split('\n').forEach((linha, i) => {
    // Concatenação em partes é o jeito consagrado de neutralizar a forma sem
    // perder a legibilidade: `'sk_' + 'live_' + ...`. Não acusa.
    if (/['"]\s*\+\s*['"]/.test(linha)) return;
    for (const p of PROVEDORES) {
      if (p.re.test(linha)) {
        achados.push(`${arq.slice(raiz.length + 1)}:${i + 1}  parece credencial ${p.nome}`);
      }
    }
  });
}

if (achados.length) {
  console.error(`FALHA: ${achados.length} fixture(s) com credencial de provedor:`);
  for (const a of achados) console.error('  ' + a);
  console.error('\nO Push Protection do GitHub vai recusar o push.');
  console.error('Use um segredo GENÉRICO, que o gitleaks detecta e o GitHub aceita:');
  console.error('  JWT de exemplo do jwt.io, ou api_key_a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6');
  process.exit(1);
}

console.log('ok — nenhum fixture com credencial de provedor');
