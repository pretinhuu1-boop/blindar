// blindar fix — wraps blindar-fix.sh (LLM patch generator) e auto-fix.sh (legacy)
import { spawn } from 'node:child_process';
import { join } from 'node:path';
import { existsSync } from 'node:fs';
import kleur from '../lib/colors.js';

export default async function fix({ args, skillRoot }) {
  const cwd = process.cwd();

  // Detecta modo: --finding-id ou --auto-all → blindar-fix.sh (LLM)
  //               --check ou nada           → auto-fix.sh (legacy determinístico)
  const useLLM = !!(args['finding-id'] || args.findingId || args['auto-all'] || args.autoAll);

  if (useLLM) {
    return runBlindarFix({ args, skillRoot, cwd });
  }
  return runAutoFix({ args, skillRoot, cwd });
}

async function runBlindarFix({ args, skillRoot, cwd }) {
  // Localiza blindar-fix.sh: prioriza skill, fallback projeto
  let script = join(skillRoot, 'scripts', 'blindar-fix.sh');
  if (!existsSync(script)) {
    script = join(cwd, 'scripts', 'blindar', 'blindar-fix.sh');
  }
  if (!existsSync(script)) {
    console.error(kleur.red('❌ blindar-fix.sh não encontrado'));
    return 2;
  }

  if (!existsSync(join(cwd, '.git'))) {
    console.error(kleur.red('❌ Não está em um repo git.'));
    return 1;
  }

  if (!process.env.ANTHROPIC_API_KEY) {
    console.error(kleur.yellow('⚠  ANTHROPIC_API_KEY ausente — blindar-fix requer API key da Anthropic.'));
    return 0;
  }

  const shellArgs = [];
  const findingId = args['finding-id'] || args.findingId;
  if (findingId) shellArgs.push('--finding-id', findingId);
  if (args['auto-all'] || args.autoAll) shellArgs.push('--auto-all');
  if (args.apply) shellArgs.push('--apply');
  else shellArgs.push('--dry-run');
  if (args.branch) shellArgs.push('--branch', args.branch);
  if (args.pr) shellArgs.push('--pr');
  if (args.model) shellArgs.push('--model', args.model);

  if (!args.apply) {
    console.log(kleur.yellow('ℹ  Modo dry-run. Use --apply pra criar branch + commit.'));
    console.log('');
  }

  return new Promise((resolveP) => {
    const child = spawn('bash', [script, ...shellArgs], {
      cwd,
      stdio: 'inherit',
      env: { ...process.env, BLINDAR_DIR: join(cwd, '.blindar') },
    });
    child.on('error', (err) => {
      console.error(kleur.red(`Falha: ${err.message}`));
      resolveP(127);
    });
    child.on('exit', (code) => resolveP(code ?? 0));
  });
}

async function runAutoFix({ args, skillRoot, cwd }) {
  let script = join(cwd, 'scripts', 'blindar', 'auto-fix.sh');
  if (!existsSync(script)) {
    script = join(skillRoot, 'templates', 'checks', 'auto-fix.sh');
  }
  if (!existsSync(script)) {
    console.error(kleur.red(`❌ auto-fix.sh não encontrado`));
    return 2;
  }

  if (!existsSync(join(cwd, '.git'))) {
    console.error(kleur.red('❌ Não está em um repo git.'));
    return 1;
  }

  const shellArgs = [];
  if (args.apply) shellArgs.push('--apply');
  if (args.check) { shellArgs.push('--check', args.check); }

  if (!args.apply) {
    console.log(kleur.yellow('ℹ  Modo dry-run (sem aplicar nada). Use --apply pra aplicar de verdade.'));
    console.log('');
  }

  return new Promise((resolveP) => {
    const child = spawn('bash', [script, ...shellArgs], {
      cwd,
      stdio: 'inherit',
      env: { ...process.env, BLINDAR_DIR: join(cwd, '.blindar') },
    });
    child.on('error', (err) => {
      console.error(kleur.red(`Falha: ${err.message}`));
      resolveP(127);
    });
    child.on('exit', (code) => resolveP(code ?? 0));
  });
}
