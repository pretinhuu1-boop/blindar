// blindar terminate — decisão matemática de release-ready
import { spawn } from 'node:child_process';
import { join } from 'node:path';
import { existsSync } from 'node:fs';
import kleur from 'kleur';

export default async function terminate({ skillRoot }) {
  const cwd = process.cwd();
  let script = join(cwd, 'scripts', 'blindar', 'check-termination.sh');
  if (!existsSync(script)) {
    script = join(skillRoot, 'templates', 'checks', 'check-termination.sh');
  }

  if (!existsSync(script)) {
    console.error(kleur.red(`❌ check-termination.sh não encontrado`));
    return 2;
  }

  return new Promise((resolveP) => {
    const child = spawn('bash', [script], {
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
