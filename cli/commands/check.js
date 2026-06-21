// blindar check — wraps shell scripts em CLI Node
import { spawn, spawnSync } from 'node:child_process';
import { join, resolve } from 'node:path';
import { existsSync } from 'node:fs';
import kleur from '../lib/colors.js';

export default async function check({ args, skillRoot }) {
  const cwd = process.cwd();

  // Git é recomendado mas não obrigatório (apenas para sha em result)
  const gitCheck = spawnSync('git', ['rev-parse', '--is-inside-work-tree'], { cwd, stdio: 'ignore' });
  if (gitCheck.status !== 0 && !args.force) {
    console.error(kleur.yellow('⚠  Não está em repo git. Continuando sem git_sha em resultados (passe --force pra suprimir).'));
  }

  // Determina caminho dos scripts: prioriza scripts/blindar/ local; fallback templates/checks/ do skill
  let scriptsDir = join(cwd, 'scripts', 'blindar');
  if (!existsSync(join(scriptsDir, 'run-all.sh'))) {
    scriptsDir = join(skillRoot, 'templates', 'checks');
    console.log(kleur.yellow('⚠  scripts/blindar/ não instalado no projeto. Usando templates do skill.'));
    console.log(kleur.yellow('   Pra instalar: ' + kleur.bold('npx blindar init')));
    console.log('');
  }

  const runner = join(scriptsDir, 'run-all.sh');
  if (!existsSync(runner)) {
    console.error(kleur.red(`❌ run-all.sh não encontrado em ${runner}`));
    return 2;
  }

  // Constrói args do shell
  const shellArgs = [];
  if (args.fast) shellArgs.push('--fast');
  if (args.json) shellArgs.push('--json');

  // bash é necessário (Git Bash no Windows ou nativo Linux/macOS)
  return new Promise((resolveP) => {
    const child = spawn('bash', [runner, ...shellArgs], {
      cwd,
      stdio: 'inherit',
      env: { ...process.env, BLINDAR_DIR: join(cwd, '.blindar') },
    });
    child.on('error', (err) => {
      console.error(kleur.red(`Falha ao executar bash: ${err.message}`));
      console.error('No Windows, instale Git Bash: https://gitforwindows.org/');
      resolveP(127);
    });
    child.on('exit', (code) => resolveP(code ?? 0));
  });
}
