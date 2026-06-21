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
import mri from 'mri';
import kleur from 'kleur';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const CLI_ROOT = join(__dirname, '..');
const SKILL_ROOT = join(CLI_ROOT, '..');

const args = mri(process.argv.slice(2), {
  alias: { h: 'help', v: 'version' },
  boolean: ['help', 'version', 'fast', 'json', 'force'],
});

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
    console.error(kleur.red(`Comando desconhecido: ${cmd}`));
    console.error('');
  }
  await import('./commands/help.js').then(m => m.default({ cliRoot: CLI_ROOT, skillRoot: SKILL_ROOT }));
  process.exit(args.help ? 0 : 1);
}

try {
  const mod = await import(COMMANDS[cmd]);
  const exitCode = await mod.default({
    args, cliRoot: CLI_ROOT, skillRoot: SKILL_ROOT,
  });
  process.exit(exitCode || 0);
} catch (err) {
  console.error(kleur.red(`Erro em '${cmd}': ${err.message}`));
  if (process.env.DEBUG) console.error(err.stack);
  process.exit(1);
}
