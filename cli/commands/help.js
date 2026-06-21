// blindar help
import kleur from 'kleur';

export default function help({ cliRoot, skillRoot }) {
  console.log(kleur.bold('blindar') + ' — audita, blinda e prepara projetos pra produção');
  console.log('');
  console.log(kleur.bold('Uso:'));
  console.log('  blindar <command> [opções]');
  console.log('');
  console.log(kleur.bold('Comandos:'));
  console.log('  ' + kleur.cyan('check') + '       Roda todos os checks determinísticos no projeto atual');
  console.log('    --fast      Subset rápido (secrets + mock + config-ext)');
  console.log('    --json      Output JSON puro (pra CI)');
  console.log('');
  console.log('  ' + kleur.cyan('init') + '        Instala scripts/blindar/ + .github/workflows/ no projeto');
  console.log('    --force     Sobrescreve arquivos existentes');
  console.log('');
  console.log('  ' + kleur.cyan('terminate') + '   Decisão matemática: release-ready? (exit 0-4)');
  console.log('');
  console.log('  ' + kleur.cyan('report') + '      Gera blindar-report.html + client-report.html');
  console.log('');
  console.log('  ' + kleur.cyan('fix') + '         Aplica auto-fixes seguros (TODO/console.log/env)');
  console.log('    --apply        Aplica de verdade (cria branch + commit)');
  console.log('    --check <X>    Roda só fixes de um agente específico');
  console.log('');
  console.log('  ' + kleur.cyan('version') + '     Mostra versão');
  console.log('  ' + kleur.cyan('help') + '        Esta mensagem');
  console.log('');
  console.log(kleur.bold('Exemplos:'));
  console.log('  # Instalar no projeto');
  console.log('  ' + kleur.gray('cd seu-projeto && npx blindar init'));
  console.log('');
  console.log('  # Validar antes de commit');
  console.log('  ' + kleur.gray('npx blindar check --fast'));
  console.log('');
  console.log('  # Validar pra release');
  console.log('  ' + kleur.gray('npx blindar check && npx blindar terminate'));
  console.log('');
  console.log(kleur.bold('Skill markdown completa:'));
  console.log('  ' + kleur.gray(skillRoot));
  console.log('');
  console.log(kleur.bold('Doc:'));
  console.log('  ' + kleur.blue('https://github.com/pretinhuu1-boop/blindar'));
  return 0;
}
