// blindar report — copia templates HTML pro projeto + atualiza com aggregate.json
import { join } from 'node:path';
import { existsSync, copyFileSync, readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import kleur from '../lib/colors.js';

export default async function report({ skillRoot }) {
  const cwd = process.cwd();
  const blindarDir = join(cwd, '.blindar');
  const aggregate = join(blindarDir, 'results', 'aggregate.json');

  if (!existsSync(aggregate)) {
    console.error(kleur.red('❌ .blindar/results/aggregate.json não existe.'));
    console.error(`   Rode primeiro: ${kleur.bold('npx blindar check')}`);
    return 1;
  }

  // Copia templates HTML se ainda não estão no projeto
  const TEMPLATES = ['execution-report.html', 'client-report.html'];
  for (const tpl of TEMPLATES) {
    const src = join(skillRoot, 'templates', tpl);
    const dst = join(cwd, tpl);
    if (!existsSync(dst) && existsSync(src)) {
      copyFileSync(src, dst);
      console.log(kleur.green(`✓ Criado: ${tpl}`));
    } else if (existsSync(dst)) {
      console.log(kleur.yellow(`⏭️  ${tpl} já existe — pulando cópia`));
    }
  }

  // Atualiza o bloco <script id="blindar-data"> em cada HTML com aggregate
  const aggData = JSON.parse(readFileSync(aggregate, 'utf8'));
  const project = (() => {
    try { return JSON.parse(readFileSync(join(cwd, 'package.json'), 'utf8')).name || 'projeto'; }
    catch { return 'projeto'; }
  })();

  // Constrói payload compatível com schema dos HTMLs
  const payload = {
    schema: 'blindar/execution-report@v1',
    project,
    blindar_version: '0.24.0',
    first_run: aggData.ran_at,
    last_updated: aggData.ran_at,
    total_runs: 1,
    runs: [{
      id: `run-${Date.now()}`,
      started_at: aggData.ran_at,
      ended_at: aggData.ran_at,
      mode: 'auto',
      actions: (aggData.results || []).flatMap(r =>
        (r.findings || []).map(f => ({
          ts: r.ran_at,
          module: 0,  // não temos a info aqui, operador pode atualizar
          agent: r.agent,
          severity: f.severity,
          title: f.message,
          files: f.file ? [`${f.file}:${f.line}`] : [],
          resolved: false,
        }))
      ),
    }],
  };

  const payloadJson = JSON.stringify(payload, null, 2);

  for (const tpl of TEMPLATES) {
    const file = join(cwd, tpl);
    if (!existsSync(file)) continue;
    const html = readFileSync(file, 'utf8');
    const updated = html.replace(
      /<script id="blindar-data" type="application\/json">[\s\S]*?<\/script>/,
      `<script id="blindar-data" type="application/json">\n${payloadJson}\n</script>`
    );
    writeFileSync(file, updated);
    console.log(kleur.green(`✓ Atualizado bloco de dados: ${tpl}`));
  }

  console.log('');
  console.log(kleur.bold('Relatórios prontos:'));
  console.log(`  ${kleur.cyan('execution-report.html')}  ← técnico (timeline + módulo + agente)`);
  console.log(`  ${kleur.cyan('client-report.html')}     ← cliente (categorias de benefício)`);
  console.log('');
  console.log('Abra qualquer um no browser pra ver.');
  return 0;
}
