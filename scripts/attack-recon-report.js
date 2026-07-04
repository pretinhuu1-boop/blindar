#!/usr/bin/env node
/**
 * blindar ataque — normaliza saída do attack-recon.sh pra findings.schema.json.
 * Puro, sem deps. CommonJS.
 *
 *   node scripts/attack-recon-report.js --dir <tmp> --url <url> --out <path>
 */
'use strict';

const { readFileSync, writeFileSync, existsSync, readdirSync } = require('node:fs');
const { join } = require('node:path');
const { parseArgs } = require('node:util');

const REQUIRED_HEADERS = {
  'content-security-policy': { sev: 'high', title: 'CSP ausente (XSS mitigation faltando)' },
  'strict-transport-security': { sev: 'high', title: 'HSTS ausente (downgrade attack possível)' },
  'x-content-type-options': { sev: 'med', title: 'X-Content-Type-Options ausente (MIME sniffing)' },
  'x-frame-options': { sev: 'med', title: 'X-Frame-Options / CSP frame-ancestors ausente (clickjacking)' },
  'referrer-policy': { sev: 'med', title: 'Referrer-Policy ausente (leak de URL)' },
  'permissions-policy': { sev: 'low', title: 'Permissions-Policy ausente' },
};
const LEAKY_HEADERS = ['server', 'x-powered-by', 'x-aspnet-version', 'x-aspnetmvc-version', 'x-generator'];
const FORGOTTEN_CRIT = new Set(['.env', '.git/config', '.git/HEAD', 'database.sql', 'phpinfo.php', 'backup.zip', 'backup.tar.gz']);

function parseHeaders(rawHdr) {
  const map = {};
  for (const line of rawHdr.split(/\r?\n/)) {
    const m = line.match(/^([A-Za-z0-9-]+):\s*(.*)$/);
    if (m) map[m[1].toLowerCase()] = m[2];
  }
  const statusLine = rawHdr.split(/\r?\n/)[0] || '';
  const status = (statusLine.match(/\s(\d{3})(?:\s|$)/) || [])[1];
  return { headers: map, status: status ? Number(status) : null };
}

function checkHome(dir, url, findings) {
  const hdrPath = join(dir, 'home.hdr');
  if (!existsSync(hdrPath)) return;
  const raw = readFileSync(hdrPath, 'utf8');
  const { headers, status } = parseHeaders(raw);

  for (const [h, meta] of Object.entries(REQUIRED_HEADERS)) {
    if (!headers[h]) {
      findings.push({
        title: meta.title, lens: 'security', sev: meta.sev, file: url,
        description: `Header \`${h}\` ausente na resposta de ${url}.`,
        suggested_fix_category: 'network-security',
      });
    }
  }
  for (const h of LEAKY_HEADERS) {
    if (headers[h]) {
      findings.push({
        title: `Info leak: header ${h} expõe "${headers[h]}"`,
        lens: 'security', sev: 'low', file: url,
        description: `Servidor revela stack via header \`${h}: ${headers[h]}\`. Facilita mapeamento de CVE.`,
        suggested_fix_category: 'network-security',
      });
    }
  }
  const setCookie = headers['set-cookie'] || '';
  if (setCookie) {
    const lc = setCookie.toLowerCase();
    if (!lc.includes('httponly')) findings.push({ title: 'Cookie sem HttpOnly', lens: 'security', sev: 'high', file: url, description: 'Cookie acessível via document.cookie — XSS pode roubar sessão.', suggested_fix_category: 'access-control' });
    if (!lc.includes('secure')) findings.push({ title: 'Cookie sem Secure', lens: 'security', sev: 'high', file: url, description: 'Cookie transmissível por HTTP puro — sniff em rede.', suggested_fix_category: 'access-control' });
    if (!/samesite=(strict|lax)/i.test(lc)) findings.push({ title: 'Cookie sem SameSite (ou None)', lens: 'security', sev: 'med', file: url, description: 'Sem SameSite=Lax/Strict, CSRF fica mais fácil.', suggested_fix_category: 'access-control' });
  }
  const acao = headers['access-control-allow-origin'];
  const acac = (headers['access-control-allow-credentials'] || '').toLowerCase() === 'true';
  if (acao === '*' && acac) {
    findings.push({ title: 'CORS: `*` + credentials = configuração inválida/permissiva', lens: 'security', sev: 'high', file: url, description: 'Access-Control-Allow-Origin: * com credentials true — navegador rejeita, mas indica misconfiguration séria.', suggested_fix_category: 'network-security' });
  }
  return { headers, status };
}

function checkForgotten(dir, url, findings) {
  for (const f of readdirSync(dir)) {
    if (!f.startsWith('f_') || f.endsWith('.hdr')) continue;
    const hdrPath = join(dir, f + '.hdr');
    if (!existsSync(hdrPath)) continue;
    const { status } = parseHeaders(readFileSync(hdrPath, 'utf8'));
    if (status !== 200) continue;
    const bodyPath = join(dir, f);
    const body = existsSync(bodyPath) ? readFileSync(bodyPath, 'utf8').slice(0, 400) : '';
    const path = f.replace(/^f_/, '').replace(/__/g, '/').replace('/', '.');
    const isCrit = FORGOTTEN_CRIT.has(path);
    findings.push({
      title: `Arquivo exposto publicamente: /${path}`,
      lens: 'security', sev: isCrit ? 'crit' : 'med', file: `${url}/${path}`,
      description: `GET /${path} retornou 200. ${isCrit ? 'CRÍTICO: contém credenciais/dados sensíveis.' : 'Pode vazar metadados/config.'} Preview: ${body.slice(0, 120).replace(/\s+/g, ' ')}`,
      suggested_fix_category: isCrit ? 'runtime-secrets' : 'network-security',
    });
  }
}

function checkDebug(dir, url, findings) {
  for (const f of readdirSync(dir)) {
    if (!f.startsWith('d_') || f.endsWith('.hdr')) continue;
    const hdrPath = join(dir, f + '.hdr');
    if (!existsSync(hdrPath)) continue;
    const { status } = parseHeaders(readFileSync(hdrPath, 'utf8'));
    if (status !== 200) continue;
    const path = f.replace(/^d_/, '').replace(/__/g, '/');
    findings.push({
      title: `Endpoint de debug/documentação exposto: /${path}`,
      lens: 'security', sev: 'high', file: `${url}/${path}`,
      description: `GET /${path} retornou 200 — endpoint de debug ou docs interno acessível publicamente.`,
      suggested_fix_category: 'devops',
    });
  }
}

function checkTls(dir, url, findings) {
  const p = join(dir, 'tls.txt');
  if (!existsSync(p)) return;
  const t = readFileSync(p, 'utf8');
  if (/Protocol\s*:\s*(SSLv2|SSLv3|TLSv1(\.0)?)/i.test(t)) {
    findings.push({ title: 'TLS: versão obsoleta habilitada', lens: 'security', sev: 'high', file: url, description: 'Handshake completou em SSLv3/TLS 1.0 — deprecado. Force TLS 1.2+.', suggested_fix_category: 'cryptography' });
  }
  const notAfter = (t.match(/NotAfter:\s*(.+)/) || [])[1];
  if (notAfter) {
    const days = Math.round((new Date(notAfter) - new Date()) / 86400000);
    if (days < 30) findings.push({ title: `Certificado TLS expira em ${days} dias`, lens: 'security', sev: 'high', file: url, description: `NotAfter: ${notAfter}. Renove antes que quebre.`, suggested_fix_category: 'cryptography' });
  }
}

function checkCt(dir, url, findings) {
  const p = join(dir, 'crt.json');
  if (!existsSync(p)) return;
  let arr = [];
  try { arr = JSON.parse(readFileSync(p, 'utf8')); } catch { return; }
  const subs = new Set();
  for (const e of arr) String(e.name_value || '').split('\n').forEach((s) => subs.add(s.toLowerCase()));
  const flagged = [...subs].filter((s) => /(stg|staging|dev|admin|internal|preprod|test)\./i.test(s));
  if (flagged.length) {
    findings.push({
      title: `Subdomínios sensíveis expostos via Certificate Transparency: ${flagged.slice(0, 5).join(', ')}${flagged.length > 5 ? '…' : ''}`,
      lens: 'security', sev: 'med', file: url,
      description: `crt.sh revela subdomínios que sugerem ambientes internos publicamente conhecidos. Considere HSTS-preload sem wildcard, ou colocar staging atrás de VPN.`,
      suggested_fix_category: 'network-security',
    });
  }
}

function main(argv) {
  const { values } = parseArgs({ args: argv, options: { dir: { type: 'string' }, url: { type: 'string' }, out: { type: 'string' } } });
  if (!values.dir || !values.url || !values.out) { console.error('uso: --dir <tmp> --url <u> --out <p>'); return 2; }
  const findings = [];
  checkHome(values.dir, values.url, findings);
  checkForgotten(values.dir, values.url, findings);
  checkDebug(values.dir, values.url, findings);
  checkTls(values.dir, values.url, findings);
  checkCt(values.dir, values.url, findings);
  writeFileSync(values.out, JSON.stringify({ findings }, null, 2));
  const crit = findings.filter((f) => f.sev === 'crit').length;
  const high = findings.filter((f) => f.sev === 'high').length;
  console.log(`[recon] ${findings.length} findings (${crit} crit, ${high} high) → ${values.out}`);
  return 0;
}

module.exports = { parseHeaders, checkHome, checkForgotten };
if (require.main === module) process.exit(main(process.argv.slice(2)));
