#!/usr/bin/env node
// Contrato do gerador de "como reproduzir". Prova que cada categoria de achado
// recebe passos NÃO-vazios e, onde faz sentido, um comando de confirmação — e
// que a categorização não cai tudo no 'generic'.
import { reproFor, categorize, reproFromResults } from '../scripts/manual-verification.mjs';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

let ok = 0, fail = 0;
const eq = (nome, got, want) => {
  if (got === want) { console.log(`  ok  - ${nome}`); ok++; }
  else { console.log(`  FAIL- ${nome}: got ${JSON.stringify(got)} want ${JSON.stringify(want)}`); fail++; }
};
const truthy = (nome, v) => { if (v) { console.log(`  ok  - ${nome}`); ok++; } else { console.log(`  FAIL- ${nome}`); fail++; } };

// 1. Categorização por agente + mensagem
eq('bundle-secret por agente', categorize({ agent: 'check-client-bundle-secrets', message: 'x' }), 'bundle-secret');
eq('token-storage por mensagem', categorize({ agent: 'check-auth-premium', message: 'Token em storage legível por JS' }), 'token-storage');
eq('secret por gitleaks', categorize({ agent: 'check-gitleaks', message: 'Secret hardcoded: aws' }), 'secret');
eq('security-header', categorize({ agent: 'check-headers-security', message: 'Missing header Strict-Transport-Security' }), 'security-header');
eq('sast por semgrep', categorize({ agent: 'check-semgrep', message: 'code-string-concat' }), 'sast');
eq('csrf', categorize({ agent: 'check-cors-csrf', message: 'sem CSRF token' }), 'csrf');
eq('infra', categorize({ agent: 'check-infra-exposure', message: 'porta 6379 exposta' }), 'infra-exposure');
eq('generic fallback', categorize({ agent: 'check-desconhecido', message: 'algo qualquer' }), 'generic');

// 2. Toda categoria devolve passos não-vazios
for (const c of ['bundle-secret', 'secret', 'token-storage', 'security-header', 'csrf', 'sast', 'rate-limit', 'runtime-leak', 'infra-exposure', 'generic']) {
  const r = reproFor({ agent: `check-${c}`, message: c, file: 'src/x.ts', line: 3 });
  truthy(`${c}: steps não-vazio`, Array.isArray(r.steps) && r.steps.length >= 1 && r.steps.every((s) => typeof s === 'string' && s.length));
}

// 3. Categorias com proof-of-work têm comando automated
truthy('bundle-secret tem comando', !!reproFor({ agent: 'check-client-bundle-secrets', message: 'x', file: 'dist/a.js' }).automated);
truthy('token-storage tem comando', !!reproFor({ agent: 'check-auth-premium', message: 'localStorage token', file: 'src/a.ts' }).automated);

// 4. reproFromResults lê um result real e enriquece
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'mv-'));
fs.writeFileSync(path.join(tmp, 'check-auth-premium.json'), JSON.stringify({
  agent: 'check-auth-premium',
  findings: [{ severity: 'crit', message: 'Token em storage legível por JS (XSS/CDP roubam)', file: 'src/auth.ts', line: 3 }],
}));
const itens = reproFromResults(tmp);
eq('reproFromResults conta 1', itens.length, 1);
eq('categoria vinda do result', itens[0]?.repro.category, 'token-storage');
truthy('finding herdou o agent', itens[0]?.finding.agent === 'check-auth-premium');
fs.rmSync(tmp, { recursive: true, force: true });

console.log(`\n${ok} ok, ${fail} fail`);
process.exit(fail ? 1 : 0);
