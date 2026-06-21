// blindar init — wraps install-deterministic-checks.sh
import { spawn } from 'node:child_process';
import { join } from 'node:path';
import { existsSync } from 'node:fs';
import kleur from '../lib/colors.js';

export default async function init({ args, skillRoot }) {
  const installer = join(skillRoot, 'scripts', 'install-deterministic-checks.sh');
  if (!existsSync(installer)) {
    console.error(kleur.red(`❌ installer não encontrado: ${installer}`));
    return 2;
  }

  if (!existsSync(join(process.cwd(), '.git'))) {
    console.error(kleur.red('❌ Não está em um repositório git. Rode `git init` primeiro.'));
    return 1;
  }

  const shellArgs = [];
  if (args.force) shellArgs.push('--force');

  return new Promise((resolveP) => {
    const child = spawn('bash', [installer, ...shellArgs], {
      cwd: process.cwd(),
      stdio: 'inherit',
    });
    child.on('error', (err) => {
      console.error(kleur.red(`Falha ao executar installer: ${err.message}`));
      console.error('No Windows, instale Git Bash: https://gitforwindows.org/');
      resolveP(127);
    });
    child.on('exit', (code) => resolveP(code ?? 0));
  });
}
