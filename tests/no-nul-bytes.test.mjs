// Nenhum arquivo versionado pode conter byte NUL.
//
// Existe porque isso já aconteceu DUAS vezes nesta base, das duas pela mesma
// via: gerar shell que contém JavaScript inline, com escape passando por mais de
// uma camada. Um `\0` entrou no lugar de um espaço dentro de um `.join()`.
//
// O que torna caro é como falha. O script continua rodando — bash não se importa
// com NUL no meio de uma string — mas o git passa a tratar o arquivo como
// BINÁRIO. Some o diff na revisão, some o blame, e uma correção de segurança
// vira "Bin 2296 -> 6355 bytes" no pull request. Ninguém revisa o que não vê.
//
// Foi assim que a segunda ocorrência apareceu: não por erro de execução, mas
// porque `git diff --stat` disse "Bin" onde deveria dizer linhas.
//
// O teste é bobo de propósito. O bug não é sutil; o que faltava era alguém
// olhando.

import { readFileSync } from 'node:fs';
import { execSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const raiz = join(dirname(fileURLToPath(import.meta.url)), '..');

const arquivos = execSync('git ls-files', {
  cwd: raiz, encoding: 'utf8', maxBuffer: 1 << 28,
}).trim().split('\n').filter(Boolean);

const culpados = [];
for (const arq of arquivos) {
  let buf;
  try { buf = readFileSync(join(raiz, arq)); } catch { continue; }
  const i = buf.indexOf(0);
  if (i === -1) continue;
  // Imagem e binário legítimo passam; o alvo é fonte que virou binário sem querer.
  if (/\.(png|jpe?g|gif|ico|pdf|zip|gz|woff2?|ttf|eot|wasm|exe|dll)$/i.test(arq)) continue;
  let linha = 1;
  for (let k = 0; k < i; k++) if (buf[k] === 10) linha++;
  culpados.push(`${arq}:${linha} (offset ${i})`);
}

if (culpados.length) {
  console.error('FALHA: byte NUL em arquivo de texto versionado:');
  for (const c of culpados) console.error('  ' + c);
  console.error('\nO git trata esses arquivos como binários: o diff some da revisão.');
  process.exit(1);
}

console.log(`ok — ${arquivos.length} arquivos versionados, nenhum byte NUL`);
