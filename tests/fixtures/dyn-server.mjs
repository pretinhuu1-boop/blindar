#!/usr/bin/env node
// Alvo vivo para os testes da camada dinâmica.
//
// Precisa ser um PROCESSO separado, não um servidor no mesmo Node do teste:
// o teste usa spawnSync para rodar os checks, e spawnSync bloqueia o event
// loop — o servidor ficaria sem aceitar conexão justamente durante a medição,
// e todo probe voltaria 000. Foi assim que a primeira versão deste teste
// "provou" que os checks não exercitavam nada.
//
// Uso: node dyn-server.mjs <bad|good> [commit]
// Escreve "READY <porta>" no stdout quando estiver aceitando conexão.

import { createServer } from 'node:http';

const mode = process.argv[2] === 'good' ? 'good' : 'bad';
const commit = process.argv[3] || 'deadbee';

const server = createServer((req, res) => {
  const url = req.url || '/';

  if (url.startsWith('/healthz')) {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    return res.end(JSON.stringify({ ok: true, commit }));
  }
  if (url === '/') {
    res.writeHead(200, { 'Content-Type': 'text/plain' });
    return res.end('home');
  }

  if (mode === 'bad') {
    // Dois defeitos de uma vez: 500 onde cabia 404/400, e rastro de execução
    // no corpo — caminho de arquivo, linha e coluna entregues ao cliente.
    res.writeHead(500, { 'Content-Type': 'text/html' });
    return res.end(
      '<pre>TypeError: x is not a function\n' +
      '    at Object.handler (/app/src/router.js:42:11)\n' +
      '    at node_modules/express/lib/router/index.js:1:1</pre>');
  }

  if (req.method === 'POST' && url.startsWith('/api')) {
    res.writeHead(400, { 'Content-Type': 'application/json' });
    return res.end(JSON.stringify({ error: 'corpo invalido' }));
  }
  res.writeHead(404, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({ error: 'nao encontrado' }));
});

server.listen(0, '127.0.0.1', () => {
  process.stdout.write('READY ' + server.address().port + '\n');
});
