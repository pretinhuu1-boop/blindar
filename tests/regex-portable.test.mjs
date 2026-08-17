// Padrões de busca precisam valer em ripgrep 13, não só no mais novo.
//
// O Debian estável e o Ubuntu LTS ainda entregam ripgrep 13. Ele é mais estrito
// que o 15 em alguns escapes, e a diferença não aparece como erro no relatório:
// o padrão morre, `|| true` engole, o arquivo de saída fica vazio, e ausência de
// resultado vira achado.
//
// Foi assim que o check-observability passou a dizer "sem health endpoints" num
// projeto que tem `/healthz` e `/health/ready`. Só apareceu rodando em container
// Linux — em máquina com ripgrep novo o padrão funcionava, então quem escreveu
// nunca viu, e quem rodou achou que o projeto é que estava errado.
//
// O erro concreto era `\/`: escapar a barra é ideia de JavaScript, onde ela
// fecha o literal de regex. Em ERE e em PCRE a barra não é especial, e o rg 13
// responde "regex parse error" a um escape que não reconhece.

import { readFileSync, readdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const raiz = join(dirname(fileURLToPath(import.meta.url)), '..');
const dir = join(raiz, 'templates', 'checks');

// Escapes que o ripgrep 13 recusa, com o que usar no lugar.
const proibidos = [
  { re: /\\\//, nome: '\\/', porque: 'a barra não é especial em regex; o rg 13 recusa o escape', use: '/' },
];

const falhas = [];
for (const arq of readdirSync(dir).filter((f) => f.endsWith('.sh'))) {
  const texto = readFileSync(join(dir, arq), 'utf8');
  texto.split('\n').forEach((linha, i) => {
    // Só linhas que realmente invocam busca — comentário explicando o problema
    // não é o problema, e este arquivo existe justamente para ser citado neles.
    if (!/^\s*[A-Z_]*=?\$?\(?\s*(rg|grep)\s/.test(linha) && !/\|\s*(rg|grep)\s/.test(linha)) return;
    if (/^\s*#/.test(linha)) return;
    for (const p of proibidos) {
      if (p.re.test(linha)) {
        falhas.push(`${arq}:${i + 1}  usa ${p.nome} — ${p.porque} (use ${p.use})`);
      }
    }
  });
}

if (falhas.length) {
  console.error(`FALHA: ${falhas.length} padrão(ões) que quebram em ripgrep 13:`);
  for (const f of falhas) console.error('  ' + f);
  console.error('\nO padrão não falha alto: ele morre, o resultado fica vazio,');
  console.error('e ausência de resultado é lida como achado.');
  process.exit(1);
}

console.log('ok — nenhum padrão de busca usa escape recusado pelo ripgrep 13');
