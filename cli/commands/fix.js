// blindar fix — wraps auto-fix.sh
import { spawn } from 'node:child_process';
import { join } from 'node:path';
import { existsSync } from 'node:fs';
import kleur from 'kleur';

export default async function fix({ args, skillRoot }) {
  const cwd = process.cwd();

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
