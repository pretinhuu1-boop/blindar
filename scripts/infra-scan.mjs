#!/usr/bin/env node
// infra-scan.mjs — exposição de infraestrutura externa (portas perigosas + reputação de IP).
//
// Absorvido do Sentinela (src/infra/tcp-scanner.mjs + dnsbl-reputation.mjs),
// destilado para o blindar. O `attack-recon` observa só HTTP; ele NÃO vê um
// Redis/Mongo/Postgres aberto pra internet — que é o buraco de plataforma-
// lavanderia clássico. Este scanner fecha essa lacuna: conexão TCP para achar
// serviço perigoso exposto + checagem do IP em blacklists DNS (DNSBL).
//
// Externo e opt-in: precisa de um host alvo (seu, ou autorizado). Sem alvo, não
// faz nada — como todo agente de ataque do blindar.
//
// Uso:
//   node scripts/infra-scan.mjs --target host[:porta] [--json]
//
// Zero dependências (usa net + dns nativos).

import net from 'node:net';
import dns from 'node:dns';
const dnsp = dns.promises;

export const PORT_SERVICES = {
  21: 'FTP', 22: 'SSH', 23: 'Telnet', 25: 'SMTP', 80: 'HTTP', 443: 'HTTPS',
  1433: 'MS SQL Server', 3000: 'Dev App', 3306: 'MySQL Database', 3389: 'RDP',
  5000: 'Dev App', 5432: 'PostgreSQL Database', 5672: 'RabbitMQ', 6379: 'Redis Cache',
  8000: 'Dev App', 8080: 'HTTP-alt', 8443: 'HTTPS-alt', 8888: 'Dev App',
  9200: 'Elasticsearch', 11211: 'Memcached', 27017: 'MongoDB Database',
};

// Portas que, se ABERTAS pra internet, são achado de segurança.
export const DANGEROUS_PORTS = new Set([
  3306, 5432, 27017, 6379, 9200, 11211, 1433, 5672, // bancos/cache/broker
  21, 22, 23, 3389, 8888,                            // acesso remoto / dev
]);

// Portas padrão a varrer quando o alvo não especifica uma.
const DEFAULT_PORTS = [
  21, 22, 23, 25, 80, 443, 1433, 3000, 3306, 3389, 5000, 5432, 5672, 6379,
  8000, 8080, 8443, 8888, 9200, 11211, 27017,
];

// Só estes códigos PROVAM porta fechada (o host respondeu com RST). Qualquer
// outro erro é "não consegui testar", não "fechada" — nunca vira aprovação.
const CLOSED_ERR_CODES = new Set(['ECONNREFUSED', 'ECONNRESET']);

export function classifyError(code) {
  return CLOSED_ERR_CODES.has(code) ? 'CLOSED' : 'UNKNOWN';
}

// IP invertido para consulta DNSBL: 1.2.3.4 → 4.3.2.1
export function reverseIp(ip) {
  return String(ip).split('.').reverse().join('.');
}

export const DNSBL_ZONES = [
  'zen.spamhaus.org', 'bl.spamcop.net', 'b.barracudacentral.org', 'dnsbl.sorbs.net',
];

// ─── Núcleo PURO (testável sem rede): severidade/risco/recomendação por porta ───
export function getPortSecurityAdvice(port, service = PORT_SERVICES[port] || 'Serviço') {
  const isDb = [3306, 5432, 27017, 1433, 9200].includes(port);
  const isCache = [6379, 11211].includes(port);
  const isBroker = [5672].includes(port);
  const isRemote = [22, 23, 3389].includes(port);
  const isDev = [3000, 5000, 8000, 8888].includes(port);
  const isMail = [21, 25].includes(port);

  if (isDb || isCache) return {
    severity: 'crit',
    risk: `Porta ${port} (${service}) é ${isCache ? 'cache' : 'banco'} exposto à internet — força bruta de senha, exfiltração e, sem auth, leitura/escrita direta de dados/sessões.`,
    recommendation: `Fechar ${port} no firewall/security group. Bind em 127.0.0.1 ou rede privada; exigir credencial forte${isCache ? ' (ex.: requirepass no Redis)' : ''} e TLS.`,
  };
  if (isBroker) return {
    severity: 'high',
    risk: `Porta ${port} (${service}) é um message broker exposto — injeção/leitura de mensagens e possível RCE via plugins.`,
    recommendation: `Restringir ${port} à rede interna; exigir credencial e vhost isolado.`,
  };
  if (isRemote) return {
    severity: 'high',
    risk: `Porta ${port} (${service}) é acesso remoto exposto — alvo constante de brute force e ransomware.`,
    recommendation: `Whitelist de IP no firewall; SSH só por chave (sem senha) ou via VPN.`,
  };
  if (isDev) return {
    severity: 'med',
    risk: `Porta ${port} (${service}) é app/ambiente de dev exposto direto — sem WAF, rate limit ou TLS.`,
    recommendation: `Reverse proxy (Nginx/Cloudflare) na frente e bloquear acesso externo direto à ${port}.`,
  };
  if (isMail) return {
    severity: 'low',
    risk: `Porta ${port} (${service}) exposta — risco de relay de spam sem auth forte.`,
    recommendation: `Exigir auth forte e TLS; desabilitar portas legadas em claro.`,
  };
  return {
    severity: 'low',
    risk: `Porta ${port} (${service}) aberta — confirme se precisa estar exposta.`,
    recommendation: `Se não for necessária externamente, feche no firewall.`,
  };
}

// ─── Geração de findings PURA (testável): recebe portas OPEN, devolve findings ───
export function portFindings(openPorts = []) {
  const out = [];
  for (const p of openPorts) {
    if (!DANGEROUS_PORTS.has(p.port)) continue;
    const adv = getPortSecurityAdvice(p.port, p.service);
    out.push({
      severity: adv.severity,
      message: `${adv.risk} ${adv.recommendation}${p.banner ? ` [banner: ${p.banner}]` : ''}`,
      file: '', line: '',
    });
  }
  return out;
}

// Conexão TCP a uma porta. Resolve OPEN/CLOSED/FILTERED/UNKNOWN.
function checkPort(host, port, timeout = 1500) {
  return new Promise((resolve) => {
    const service = PORT_SERVICES[port] || 'Custom';
    const start = Date.now();
    const sock = new net.Socket();
    sock.setTimeout(timeout);
    let banner = '';
    sock.on('connect', () => {
      sock.on('data', (d) => { banner = d.toString('utf8').trim().replace(/[\r\n]+/g, ' ').slice(0, 100); });
      setTimeout(() => {
        sock.destroy();
        resolve({ port, service, state: 'OPEN', latency_ms: Date.now() - start, banner: banner || null });
      }, 200);
    });
    sock.on('timeout', () => { sock.destroy(); resolve({ port, service, state: 'FILTERED', latency_ms: Date.now() - start }); });
    sock.on('error', (err) => { sock.destroy(); resolve({ port, service, state: classifyError(err.code), latency_ms: Date.now() - start }); });
    sock.connect(port, host);
  });
}

// Consulta o IP nas zonas DNSBL. Retorna [{zone, listed}] só das que responderam listado.
async function dnsblCheck(ip) {
  const rev = reverseIp(ip);
  const hits = [];
  await Promise.all(DNSBL_ZONES.map(async (zone) => {
    try {
      const a = await dnsp.resolve4(`${rev}.${zone}`);
      if (a && a.length) hits.push({ zone, listed: true, codes: a });
    } catch { /* NXDOMAIN = não listado; outros erros = não testável, ignora */ }
  }));
  return hits;
}

// Varredura completa de um host. `opts` permite injeção para teste (ports/dangerous/skipDnsbl).
export async function scan(host, opts = {}) {
  const ports = opts.ports || DEFAULT_PORTS;
  const results = await Promise.all(ports.map((p) => checkPort(host, p, opts.timeout || 1500)));
  const open = results.filter((r) => r.state === 'OPEN');

  let ip = null, dnsbl = [];
  if (!opts.skipDnsbl) {
    try {
      ip = net.isIP(host) ? host : (await dnsp.resolve4(host))[0];
      if (ip) dnsbl = await dnsblCheck(ip);
    } catch { /* sem resolução → sem DNSBL, não é aprovação */ }
  }

  const findings = portFindings(open);
  for (const h of dnsbl) findings.push({
    severity: 'high',
    message: `IP ${ip} está listado em blacklist DNS (${h.zone}) — reputação comprometida: e-mail cai em spam e pode indicar host abusado/comprometido.`,
    file: '', line: '',
  });

  return { host, ip, ports: results, open, dnsbl, findings };
}

// CLI
if (process.argv[1] && process.argv[1].endsWith('infra-scan.mjs')) {
  const args = process.argv.slice(2);
  const tIdx = args.indexOf('--target');
  const target = tIdx >= 0 ? args[tIdx + 1] : '';
  const asJson = args.includes('--json');
  if (!target) {
    console.error('uso: node scripts/infra-scan.mjs --target host[:porta] [--json]');
    console.error('sem alvo não há o que varrer (agente externo, opt-in).');
    process.exit(2);
  }
  let host = target.replace(/^https?:\/\//, '').replace(/\/.*$/, '');
  let ports;
  if (host.includes(':')) { const [h, p] = host.split(':'); host = h; ports = [parseInt(p, 10)]; }
  scan(host, ports ? { ports } : {}).then((res) => {
    if (asJson) { console.log(JSON.stringify(res, null, 2)); }
    else {
      console.log(`host: ${res.host}${res.ip ? ` (${res.ip})` : ''}`);
      console.log(`portas abertas: ${res.open.map((o) => `${o.port}/${o.service}`).join(', ') || 'nenhuma'}`);
      if (res.dnsbl.length) console.log(`DNSBL: listado em ${res.dnsbl.map((d) => d.zone).join(', ')}`);
      if (!res.findings.length) console.log('nenhum achado de exposição.');
      for (const f of res.findings) console.log(`  [${f.severity}] ${f.message}`);
    }
    process.exit(res.findings.some((f) => f.severity === 'crit' || f.severity === 'high') ? 1 : 0);
  });
}
