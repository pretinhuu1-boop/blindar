#!/usr/bin/env node
// Contrato do infra-scan. Lógica pura sem rede + um scan REAL contra um servidor
// TCP local (127.0.0.1), que prova o caminho de detecção ponta-a-ponta sem
// tocar em nenhum host de terceiro.
import net from 'node:net';
import {
  getPortSecurityAdvice, portFindings, reverseIp, classifyError, scan, DANGEROUS_PORTS,
} from '../scripts/infra-scan.mjs';

let ok = 0, fail = 0;
const eq = (n, g, w) => { if (g === w) { console.log(`  ok  - ${n}`); ok++; } else { console.log(`  FAIL- ${n}: got ${JSON.stringify(g)} want ${JSON.stringify(w)}`); fail++; } };
const truthy = (n, v) => { if (v) { console.log(`  ok  - ${n}`); ok++; } else { console.log(`  FAIL- ${n}`); fail++; } };

// 1. Advice puro — banco/cache expostos são crit
eq('Redis 6379 → crit', getPortSecurityAdvice(6379).severity, 'crit');
eq('MongoDB 27017 → crit', getPortSecurityAdvice(27017).severity, 'crit');
eq('Postgres 5432 → crit', getPortSecurityAdvice(5432).severity, 'crit');
eq('SSH 22 → high', getPortSecurityAdvice(22).severity, 'high');
eq('Dev app 3000 → med', getPortSecurityAdvice(3000).severity, 'med');
truthy('recomendação menciona firewall/bind', /firewall|bind|VPN|proxy/i.test(getPortSecurityAdvice(6379).recommendation));

// 2. Helpers puros
eq('reverseIp', reverseIp('1.2.3.4'), '4.3.2.1');
eq('ECONNREFUSED → CLOSED', classifyError('ECONNREFUSED'), 'CLOSED');
eq('EHOSTUNREACH → UNKNOWN', classifyError('EHOSTUNREACH'), 'UNKNOWN');

// 3. Geração de findings pura — só portas perigosas viram achado
const finds = portFindings([
  { port: 6379, service: 'Redis Cache', banner: null },
  { port: 443, service: 'HTTPS' }, // não perigosa → ignorada
]);
eq('só a perigosa vira finding', finds.length, 1);
eq('finding da perigosa é crit', finds[0]?.severity, 'crit');

// 4. Scan REAL contra servidor local: prova detecção OPEN + finding ponta-a-ponta
const test = async () => {
  // Sobe um servidor TCP numa porta perigosa (6379) em 127.0.0.1. Se estiver em
  // uso, escolhe outra da lista perigosa.
  const candidatos = [6379, 27017, 5432, 11211, 9200];
  let server, chosen;
  for (const p of candidatos) {
    try {
      await new Promise((res, rej) => {
        const s = net.createServer((c) => c.end());
        s.once('error', rej);
        s.listen(p, '127.0.0.1', () => { server = s; chosen = p; res(); });
      });
      break;
    } catch { /* porta ocupada, tenta a próxima */ }
  }
  truthy('conseguiu abrir uma porta perigosa local para o teste', !!server);
  if (server) {
    const res = await scan('127.0.0.1', { ports: [chosen], skipDnsbl: true, timeout: 1500 });
    eq(`scan detecta ${chosen} OPEN`, res.open.some((o) => o.port === chosen), true);
    eq('scan produz finding crit da porta exposta', res.findings.some((f) => f.severity === 'crit'), true);
    await new Promise((r) => server.close(r));
  }
  console.log(`\n${ok} ok, ${fail} fail`);
  process.exit(fail ? 1 : 0);
};
test();
