#!/usr/bin/env node
// Corrige, de forma SEGURA e idempotente, os 3 bugs sistêmicos dos checks
// determinísticos documentados em docs/CHECK-BUGS-AUDIT.md. Opera só em tokens
// de flag do `rg` (nunca dentro de strings de padrão) — NÃO é sed cego.
//
//   Bug 1: `rg -cE` / `-nE` / `-lE` / `-hoE` / `-ciE` / `-niE`  → remove o `E`
//          (`-E` é --encoding no ripgrep, não "extended regex"). `-E` sozinho → some.
//   Bug 2: `IGNORE=('!x' '!y')`  → `IGNORE=(-g '!x' -g '!y')`
//          (sem `-g`, o `!x` vira path posicional que o rg tenta abrir → 0 hits).
//   Bug 3: `grep -c ... || echo 0`  → `grep -c ...`
//          (grep -c já emite "0" e sai 1; o `|| echo 0` gera saída dupla "0\n0").
//
// Uso: node scripts/fix-check-syntax.js [--dry] [--dir templates/checks]
// Exit 0 sempre; imprime resumo do que mudou.

import { readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';

const __dirname = dirname(fileURLToPath(import.meta.url));
const { values } = parseArgs({
  options: {
    dir: { type: 'string', default: join(__dirname, '..', 'templates', 'checks') },
    dry: { type: 'boolean', default: false },
  },
});

// Remove o char 'E' de um bundle de short-flags do rg, preservando os demais.
// Retorna '' se o bundle era só '-E' (deve ser removido inteiro).
function stripEncodingFlag(bundle) {
  // bundle começa com '-' e é só letras (ex: -cE, -nE, -hoE, -E)
  const letters = bundle.slice(1).replace(/E/g, '');
  return letters ? '-' + letters : '';
}

// Corrige flags do rg numa linha, tokenizando por espaços mas respeitando aspas.
function fixRgFlags(line) {
  if (!/\brg\s+-/.test(line)) return line;
  // Processa cada ocorrência de `rg` seguida de flags. Só toca tokens `-[A-Za-z]+`
  // que venham logo após `rg` ou após outro flag — para antes do primeiro token
  // não-flag (o padrão/pattern), que nunca é alterado.
  return line.replace(/\brg((?:\s+-[A-Za-z]+(?:\s+\d+)?)+)/g, (m, flagsPart) => {
    const tokens = flagsPart.trim().split(/\s+/);
    const out = [];
    for (let i = 0; i < tokens.length; i++) {
      const t = tokens[i];
      // -A/-B/-C tomam um argumento numérico — não mexer no número
      if (/^-[ABC]$/.test(t)) { out.push(t); if (/^\d+$/.test(tokens[i + 1] || '')) out.push(tokens[++i]); continue; }
      if (/^-[A-Za-z]+$/.test(t) && t.includes('E')) {
        const fixed = stripEncodingFlag(t);
        if (fixed) out.push(fixed);
        // se '' → flag era -E sozinho → dropado
      } else {
        out.push(t);
      }
    }
    return 'rg ' + out.join(' ');
  });
}

// Corrige IGNORE=(...) inserindo -g antes de cada item, se ainda não tiver.
function fixIgnoreArray(line) {
  const m = line.match(/^(\s*[A-Z_]*IGNORE[A-Z_]*=\()(.*)(\)\s*)$/);
  if (!m) return line;
  const [, head, body, tail] = m;
  if (body.includes('-g ')) return line; // já corrigido
  // items separados por espaço, cada um tipo '!x' ou "!x"
  const items = body.match(/(['"])[^'"]*\1/g);
  if (!items) return line;
  const rebuilt = items.map((it) => `-g ${it}`).join(' ');
  return head + rebuilt + tail;
}

// Remove ` || echo 0` quando a linha usa grep -c.
function fixGrepCEcho(line) {
  if (!/grep\s+-[A-Za-z]*c/.test(line)) return line;
  return line.replace(/\s*\|\|\s*echo\s+0/g, '');
}

const files = readdirSync(values.dir).filter((f) => /^check-.*\.sh$/.test(f));
let changed = 0;
const summary = [];

for (const f of files) {
  const path = join(values.dir, f);
  const src = readFileSync(path, 'utf8');
  const lines = src.split('\n');
  let hits = 0;
  const out = lines.map((line) => {
    let l = line;
    const before = l;
    l = fixRgFlags(l);
    l = fixIgnoreArray(l);
    l = fixGrepCEcho(l);
    if (l !== before) hits++;
    return l;
  });
  if (hits > 0) {
    changed++;
    summary.push(`  ${f}: ${hits} linha(s)`);
    if (!values.dry) writeFileSync(path, out.join('\n'));
  }
}

console.log(`fix-check-syntax: ${changed}/${files.length} arquivo(s) ${values.dry ? '(dry-run)' : 'corrigido(s)'}`);
summary.forEach((s) => console.log(s));
