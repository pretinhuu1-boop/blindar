#!/usr/bin/env node
// manual-verification.mjs — "Como reproduzir" por achado.
//
// Absorvido do Sentinela (src/generators/manual-verification.mjs), adaptado para
// os achados de CÓDIGO do blindar. Um finding do blindar é
// {severity, message, file, line} vindo de um check determinístico; aqui ele
// ganha PASSOS de reprodução: como localizar no código, como confirmar com uma
// ferramenta, e — quando faz sentido — como ver ao vivo no navegador/curl.
//
// Por que isto existe: a lição mais cara deste projeto é que achado sem prova
// reproduzível não é achado, é alegação. O relatório do `testes ban` dizia
// "successfully demonstrated" sem um único passo que outra pessoa pudesse
// refazer. Um finding que carrega o próprio "como reproduzir" não pode blefar.
//
// Uso:
//   node scripts/manual-verification.mjs [.blindar/results]   # lista tudo + repro
//   import { reproFor } from './manual-verification.mjs'       # como lib
//
// Zero dependências.

import fs from 'node:fs';
import path from 'node:path';

// URL alvo (opcional): sem ela, os passos "ao vivo" viram DevTools em vez de curl.
const TARGET_URL = process.env.BLINDAR_TARGET_URL || '';

// Categoriza um finding por agente de origem + palavras da mensagem.
// Retorna uma chave estável usada pelo mapa de repro abaixo.
export function categorize({ agent = '', message = '' } = {}) {
  const a = String(agent).toLowerCase();
  const m = String(message).toLowerCase();
  const has = (...ks) => ks.some((k) => m.includes(k));

  if (a.includes('client-bundle-secrets') || has('bundle servido ao browser', 'no bundle')) return 'bundle-secret';
  if (a.includes('gitleaks') || a.includes('check-secrets') || has('secret hardcoded', 'secret hardcoded:')) return 'secret';
  if (has('storage legível por js', 'localstorage', 'sessionstorage', 'document.cookie')) return 'token-storage';
  if (a.includes('headers-security') || a.includes('network-security') || has('header', 'csp', 'hsts', 'x-frame')) return 'security-header';
  if (a.includes('cors-csrf') || has('csrf', 'cors')) return 'csrf';
  if (a.includes('semgrep') || has('sql', 'injection', 'inject', 'xss', 'eval', 'code-string-concat')) return 'sast';
  if (a.includes('rate-limit') || has('rate limit', 'rate-limit', '429')) return 'rate-limit';
  if (a.includes('runtime-secrets') || has('process.env', 'query string', 'stack')) return 'runtime-leak';
  if (a.includes('infra') || has('porta', 'port', 'exposed', 'exposta', 'dnsbl')) return 'infra-exposure';
  return 'generic';
}

// Passo "ao vivo": curl se houver URL, DevTools caso contrário.
function liveHeaderStep(header) {
  if (TARGET_URL) {
    return {
      note: `Confirme na resposta real do servidor:`,
      cmd: `curl -skD - "${TARGET_URL}" -o /dev/null | grep -i "${header || 'strict-transport-security'}"`,
    };
  }
  return {
    note: `Sem URL alvo (BLINDAR_TARGET_URL): confirme no navegador —`,
    cmd: `F12 → Network → recarregue a página → clique no documento → aba Headers → procure "${header || 'o header'}"`,
  };
}

// Mapa de repro por categoria. Cada um devolve { steps:[], automated, live? }.
// `automated` é um comando que, rodado, confirma o achado (proof-of-work).
const MAP = {
  'bundle-secret': (f) => ({
    steps: [
      `Abra o arquivo do bundle: ${f.file || 'dist/**'}${f.line ? ':' + f.line : ''}`,
      `Confirme que a chave secreta está no JS que o browser baixa (não é chave pública pk_/NEXT_PUBLIC_).`,
      `No navegador: F12 → Sources → abra o bundle → busque o prefixo da chave (sk_live_, key-, AKIA...).`,
      `CORREÇÃO: mova para o servidor / env não-pública, remova do bundle e ROTACIONE a chave (ela já vazou).`,
    ],
    automated: `grep -rEIno "(sk_live_|sk_test_|rk_(live|test)_|key-[0-9a-f]{32}|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{35})" dist build out .next/static public 2>/dev/null`,
  }),
  secret: (f) => ({
    steps: [
      `Localize: ${f.file || '<arquivo>'}${f.line ? ':' + f.line : ''}`,
      `Confirme com o scanner e veja se está também no histórico git.`,
      `CORREÇÃO: remova, use variável de ambiente/secret manager, e ROTACIONE — segredo commitado é segredo comprometido.`,
    ],
    automated: `gitleaks detect --no-git --redact --report-format=json --report-path=/dev/stdout`,
  }),
  'token-storage': (f) => ({
    steps: [
      `Localize: ${f.file || '<arquivo>'}${f.line ? ':' + f.line : ''}`,
      `No app rodando e LOGADO: F12 → Application → Storage (Local/Session) ou Cookies → veja o token gravado por JS.`,
      `Prova de que XSS/CDP leem: no Console rode  localStorage.getItem('token') || sessionStorage.getItem('token')  → retorna o valor.`,
      `CORREÇÃO: token de sessão em cookie httpOnly + secure + sameSite (JS não lê httpOnly).`,
    ],
    automated: `rg -n "(localStorage|sessionStorage)\\.setItem.*['\\"](token|access[_-]?token|jwt|auth)|document\\.cookie\\s*=.*(token|jwt|session)" --type ts --type js`,
  }),
  'security-header': (f) => {
    const h = (f.message || '').match(/(strict-transport|content-security|x-frame|referrer|permissions|x-content|coop|coep|cross-origin)[a-z-]*/i);
    const live = liveHeaderStep(h ? h[0] : '');
    return {
      steps: [
        `${live.note}`,
        `→ ${live.cmd}`,
        `Ausência do header na resposta confirma o achado.`,
        `CORREÇÃO: adicione o header no servidor/edge (nginx add_header, ou middleware/helmet).`,
      ],
      automated: TARGET_URL ? live.cmd : '',
    };
  },
  csrf: () => ({
    steps: [
      `Identifique um endpoint que muda estado (POST/PUT/DELETE) sem token anti-CSRF nem checagem de Origin/SameSite.`,
      `Prova: monte um POST cross-site (form/página externa) apontando para o endpoint com a sessão do usuário.`,
      `Se a ação acontece sem token próprio, é CSRF.`,
      `CORREÇÃO: token anti-CSRF por sessão + cookies SameSite=Lax/Strict + valide Origin/Referer.`,
    ],
    automated: '',
  }),
  sast: (f) => ({
    steps: [
      `Abra: ${f.file || '<arquivo>'}${f.line ? ':' + f.line : ''}`,
      `Leia o trecho — a regra semgrep no message diz o padrão (ex.: input em query/eval sem sanitização).`,
      `Reproduza a regra isolada para confirmar que não é falso positivo.`,
      `CORREÇÃO: query parametrizada (SQLi), escape/encoding na saída (XSS), remover eval de input externo.`,
    ],
    automated: `semgrep --config=p/security-audit ${f.file || '.'} --json`,
  }),
  'rate-limit': () => ({
    steps: [
      `Escolha o endpoint sensível (login, OTP, reset de senha).`,
      `Dispare N requisições rápidas e veja se em algum momento retorna 429/limite.`,
      `Sem 429 sob rajada = sem rate limit efetivo.`,
      `CORREÇÃO: limite por IP+conta (ex.: token bucket), com resposta 429 e Retry-After.`,
    ],
    automated: TARGET_URL ? `for i in $(seq 1 50); do curl -s -o /dev/null -w "%{http_code}\\n" "${TARGET_URL}"; done | sort | uniq -c` : '',
  }),
  'runtime-leak': (f) => ({
    steps: [
      `Localize: ${f.file || '<arquivo>'}${f.line ? ':' + f.line : ''}`,
      `Confirme que o valor sensível chega a log/cliente/URL (não só existe no código).`,
      `CORREÇÃO: nunca logar objeto inteiro de req/user; segredo só via header Authorization, nunca em query string.`,
    ],
    automated: `rg -n "process\\.env\\.[A-Z_]+|console\\.(log|info|debug|error)\\(.*(token|secret|password)" --type ts --type js`,
  }),
  'infra-exposure': (f) => ({
    steps: [
      `${f.message || 'Porta/serviço exposto'} — confirme que a porta responde de fora da rede interna.`,
      TARGET_URL ? `Teste a conexão TCP direto no host.` : `Rode o scan de infra com o host alvo.`,
      `CORREÇÃO: feche a porta no firewall/security group; exponha banco/cache só na rede privada; exija auth+TLS.`,
    ],
    automated: TARGET_URL ? `node scripts/infra-scan.mjs --target ${TARGET_URL.replace(/^https?:\/\//, '').replace(/\/.*$/, '')}` : '',
  }),
  generic: (f) => ({
    steps: [
      `Abra: ${f.file || '(sem arquivo)'}${f.line ? ':' + f.line : ''}`,
      `Re-rode o check que gerou este achado para confirmar que ainda dispara.`,
      `Corrija e re-rode: o check deixar de disparar é a prova do fix.`,
    ],
    automated: '',
  }),
};

// API pública: recebe um finding (+ agent opcional) e devolve { category, steps, automated }.
export function reproFor(finding = {}) {
  const category = categorize(finding);
  const out = (MAP[category] || MAP.generic)(finding);
  return { category, steps: out.steps || [], automated: out.automated || '' };
}

// Lê todos os results de .blindar/results/ e devolve [{agent, finding, repro}].
export function reproFromResults(dir) {
  const out = [];
  let files = [];
  try { files = fs.readdirSync(dir).filter((f) => f.endsWith('.json')); } catch { return out; }
  for (const fname of files) {
    let j;
    try { j = JSON.parse(fs.readFileSync(path.join(dir, fname), 'utf8')); } catch { continue; }
    const agent = j.agent || fname.replace(/\.json$/, '');
    for (const f of (Array.isArray(j.findings) ? j.findings : [])) {
      const finding = { agent, ...f };
      out.push({ agent, finding, repro: reproFor(finding) });
    }
  }
  return out;
}

// CLI: lista tudo com a repro.
if (import.meta.url === `file://${process.argv[1]}` || process.argv[1]?.endsWith('manual-verification.mjs')) {
  const dir = process.argv[2] || '.blindar/results';
  const itens = reproFromResults(dir);
  if (!itens.length) {
    console.log(`sem findings em ${dir} (rode os checks antes, ou passe outro diretório).`);
    process.exit(0);
  }
  for (const { agent, finding, repro } of itens) {
    const loc = finding.file ? ` — ${finding.file}${finding.line ? ':' + finding.line : ''}` : '';
    console.log(`\n[${finding.severity || '?'}] ${finding.message || '(sem mensagem)'}${loc}`);
    console.log(`  origem: ${agent}  |  categoria: ${repro.category}`);
    console.log(`  como reproduzir:`);
    repro.steps.forEach((s, i) => console.log(`    ${i + 1}. ${s}`));
    if (repro.automated) console.log(`  comando de confirmação:\n    ${repro.automated}`);
  }
  console.log(`\n${itens.length} finding(s) com passos de reprodução.`);
}
