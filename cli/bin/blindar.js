#!/usr/bin/env node
// blindar CLI — entry point
// Uso: blindar <command> [opções]
//
// Comandos:
//   check         Roda todos os checks determinísticos
//   check --fast  Subset rápido (secrets + mock + config-ext)
//   init          Instala scripts no projeto-alvo
//   terminate     Decisão matemática de release-ready
//   report        Gera blindar-report.html + client-report.html
//   version       Mostra versão
//   help          Lista comandos

import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { readFileSync } from 'node:fs';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const CLI_ROOT = join(__dirname, '..');
const SKILL_ROOT = join(CLI_ROOT, '..');

// Parser de args nativo (zero deps) — substitui mri
function parseArgs(argv) {
  const out = { _: [] };
  const flags = new Set(['help', 'h', 'version', 'v', 'fast', 'json', 'force', 'apply']);
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--help' || a === '-h') out.help = true;
    else if (a === '--version' || a === '-v') out.version = true;
    else if (a.startsWith('--')) {
      const [k, v] = a.slice(2).split('=');
      if (v !== undefined) out[k] = v;
      else if (flags.has(k)) out[k] = true;
      else if (i + 1 < argv.length && !argv[i+1].startsWith('-')) { out[k] = argv[++i]; }
      else out[k] = true;
    }
    else if (a.startsWith('-')) out[a.slice(1)] = true;
    else out._.push(a);
  }
  return out;
}

// Cores ANSI mínimas (zero deps) — substitui kleur
const c = {
  red:    s => `\x1b[31m${s}\x1b[0m`,
  green:  s => `\x1b[32m${s}\x1b[0m`,
  yellow: s => `\x1b[33m${s}\x1b[0m`,
  blue:   s => `\x1b[34m${s}\x1b[0m`,
  bold:   s => `\x1b[1m${s}\x1b[0m`,
};

const args = parseArgs(process.argv.slice(2));
const cmd = args._[0] || 'help';

const COMMANDS = {
  check:      './commands/check.js',
  init:       './commands/init.js',
  terminate:  './commands/terminate.js',
  report:     './commands/report.js',
  fix:        './commands/fix.js',
  version:    './commands/version.js',
  help:       './commands/help.js',
};

if (args.version) {
  const pkg = JSON.parse(readFileSync(join(CLI_ROOT, 'package.json'), 'utf8'));
  console.log(`blindar v${pkg.version}`);
  process.exit(0);
}

if (args.help || !COMMANDS[cmd]) {
  if (!COMMANDS[cmd] && cmd !== 'help') {
    console.error(c.red(`Comando desconhecido: ${cmd}`));
    console.error('');
  }
  await import('../commands/help.js').then(m => m.default({ cliRoot: CLI_ROOT, skillRoot: SKILL_ROOT, c }));
  process.exit(args.help ? 0 : 1);
}

try {
  const mod = await import('../' + COMMANDS[cmd].replace('./', ''));
  const exitCode = await mod.default({
    args, cliRoot: CLI_ROOT, skillRoot: SKILL_ROOT, c,
  });
  process.exit(exitCode || 0);
} catch (err) {
  console.error(c.red(`Erro em '${cmd}': ${err.message}`));
  if (process.env.DEBUG) console.error(err.stack);
  process.exit(1);
}
