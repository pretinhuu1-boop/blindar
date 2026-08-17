// Contrato dos 14 checks .api.sh, sem gastar um token de API.
//
// Eles ficavam de fora do gate com a justificativa "precisam de LLM, logo não
// têm veredito determinístico". Metade disso é verdade: o JULGAMENTO é do
// modelo. A outra metade não é — o que o check faz com a resposta é código
// comum, e código comum tem contrato.
//
// E era código sem nenhum teste, no caminho mais escorregadio do projeto. Já
// quebrou aqui: `IFS='||'` é um CONJUNTO {|}, então o campo vazio entre os dois
// pipes deslocava tudo e TODOS os findings de API saíam com mensagem vazia e
// file/line trocados. O check reportava `failed` sem dizer o que achou, e nada
// no repositório teria pego isso.
//
// A resposta que a API devolveria é injetada por `BLINDAR_API_RESPONSE_FILE`.
// A primeira versão subia um servidor HTTP local e apontava `BLINDAR_API_URL`
// para ele — não serve: em ambiente com loopback bloqueado o teste falhava por
// causa da rede, não do contrato, e teste que falha por motivo alheio ao que
// mede acaba sendo desligado. Ler de arquivo não depende de nada.
//
// O que se verifica é o que pertence ao blindar:
//   findings com crit/high  → status `failed` e os findings chegam íntegros
//   nenhum finding          → status `passed`
//   severidade fora do enum → cai para `low`, nunca some nem vira crítico
//   resposta sem tool_use   → `skipped`, nunca `passed`
//
// A última linha é a regra da casa: resposta que não deu para interpretar é
// ausência de medição, e ausência de medição não é aprovação.

import { spawnSync } from 'node:child_process';
import { readFileSync, readdirSync, mkdtempSync, rmSync, writeFileSync, mkdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const raiz = join(dirname(fileURLToPath(import.meta.url)), '..');
const checksDir = join(raiz, 'templates', 'checks');
const apiChecks = readdirSync(checksDir).filter((f) => f.endsWith('.api.sh')).sort();

const naoApagados = [];

const respostas = {
  'com-findings': {
    content: [{
      type: 'tool_use', name: 'reportar', input: {
        findings: [
          { severity: 'crit', message: 'credencial em texto claro', file: 'src/a.js', line: '12' },
          { severity: 'INVENTADA', message: 'severidade fora do enum', file: 'src/b.js', line: '3' },
        ],
      },
    }],
    stop_reason: 'tool_use', usage: { input_tokens: 100, output_tokens: 50 },
  },
  'sem-findings': {
    content: [{ type: 'tool_use', name: 'reportar', input: { findings: [] } }],
    stop_reason: 'tool_use', usage: { input_tokens: 100, output_tokens: 10 },
  },
  'sem-tool-use': {
    content: [{ type: 'text', text: 'analisei e não vou usar a ferramenta' }],
    stop_reason: 'end_turn', usage: { input_tokens: 100, output_tokens: 10 },
  },
};

const arquivoResposta = join(tmpdir(), `blindar-api-resp-${process.pid}.json`);

// O proactive-analysis não devolve `findings`: devolve `dimensions[].risks[]`, e
// só promove a achado o que vier como crit ou high. Formato próprio, contrato
// igual — por isso a resposta é escolhida por check, e não uma só para todos.
// Assumir um formato único faria o teste medir o formato do teste.
const respostasPorCheck = {
  'check-proactive-analysis.api.sh': {
    'com-findings': {
      content: [{ type: 'tool_use', name: 'reportar', input: {
        dimensions: [{
          name: 'seguranca',
          risks: [
            { severity: 'crit', description: 'credencial em texto claro', mitigation: 'mover para env' },
            { severity: 'INVENTADA', description: 'severidade fora do enum', mitigation: 'x' },
          ],
        }],
      } }],
      stop_reason: 'tool_use', usage: { input_tokens: 100, output_tokens: 50 },
    },
    'sem-findings': {
      content: [{ type: 'tool_use', name: 'reportar', input: { dimensions: [] } }],
      stop_reason: 'tool_use', usage: { input_tokens: 100, output_tokens: 10 },
    },
    'sem-tool-use': {
      content: [{ type: 'text', text: 'analisei e não vou usar a ferramenta' }],
      stop_reason: 'end_turn', usage: { input_tokens: 100, output_tokens: 10 },
    },
  },
};

function roda(check, m) {
  const tabela = respostasPorCheck[check] || respostas;
  writeFileSync(arquivoResposta, JSON.stringify(tabela[m]));
  const dir = mkdtempSync(join(tmpdir(), 'blindar-api-'));
  // Projeto-alvo rico o bastante para os 14 passarem das PRÉ-CONDIÇÕES e
  // chegarem na chamada da API. Sem `run-report.json`, por exemplo, o
  // proactive-analysis pula antes de chamar qualquer coisa — e `skipped` por
  // pré-condição não exercita nada do que este arquivo quer medir.
  for (const d of ['src', '.blindar/results', '.github/workflows', 'docs']) {
    mkdirSync(join(dir, d), { recursive: true });
  }
  writeFileSync(join(dir, 'package.json'), JSON.stringify({
    name: 'alvo', version: '1.0.0',
    scripts: { build: 'tsc', test: 'jest' },
    dependencies: { express: '^4.19.2' },
  }, null, 2) + '\n');
  writeFileSync(join(dir, 'src', 'index.js'), [
    'import express from "express";',
    'const app = express();',
    'app.get("/", (req, res) => res.send("oi"));',
    'export default app;',
  ].join('\n') + '\n');
  writeFileSync(join(dir, 'README.md'), '# alvo\n\nProjeto de teste do contrato de API.\n');
  // Quatro dos catorze checam aplicabilidade antes de chamar a API: sem sinal de
  // RAG, vector DB ou fine-tuning eles pulam — e com razão, porque não se
  // aplicam. Mas `skipped` por não-aplicabilidade não exercita o parse da
  // resposta, que é o que este arquivo mede. O projeto sintético carrega os
  // marcadores para que os catorze cheguem ao mesmo ponto.
  writeFileSync(join(dir, 'src', 'rag.js'), [
    'import { ChromaClient } from "chromadb";',
    'const cliente = new ChromaClient({ path: process.env.CHROMA_URL });',
    'export const buscar = (q) => cliente.query({ queryTexts: [q], nResults: 5 });',
  ].join('\n') + '\n');
  writeFileSync(join(dir, 'src', 'treino.py'), [
    'from trl import SFTTrainer',
    'from transformers import TrainingArguments',
    'args = TrainingArguments(output_dir="out")',
    'trainer = SFTTrainer(model="base", args=args, train_dataset="dados.jsonl")',
  ].join('\n') + '\n');
  writeFileSync(join(dir, 'dados.jsonl'),
    '{"prompt":"oi","completion":"ola"}\n{"prompt":"tchau","completion":"ate mais"}\n');
  writeFileSync(join(dir, 'Dockerfile'), [
    'FROM node:22-alpine', 'WORKDIR /app', 'COPY . .', 'CMD ["node","src/index.js"]',
  ].join('\n') + '\n');
  writeFileSync(join(dir, '.github', 'workflows', 'ci.yml'), [
    'name: ci', 'on: [push]', 'jobs:', '  test:', '    runs-on: ubuntu-latest',
    '    steps:', '      - uses: actions/checkout@v4',
  ].join('\n') + '\n');
  writeFileSync(join(dir, '.blindar', 'run-report.json'), JSON.stringify({
    schema: 'blindar/run-report@v1', agents_total: 2, passed: 1, failed: 1,
    errored: 0, skipped: 0, coverage_pct: 100,
    findings_by_severity: { crit: 0, high: 1, med: 0, low: 0 },
  }, null, 2) + '\n');
  writeFileSync(join(dir, '.blindar', 'results', 'check-exemplo.json'), JSON.stringify({
    schema: 'blindar/check-result@v1', agent: 'check-exemplo', status: 'failed',
    exit_code: 1, findings_count: 1,
    findings: [{ severity: 'high', message: 'exemplo', file: 'src/index.js', line: '3' }],
  }, null, 2) + '\n');
  const r = spawnSync('bash', [join(checksDir, check)], {
    cwd: dir, encoding: 'utf8', timeout: 120000,
    env: {
      ...process.env,
      BLINDAR_API_RESPONSE_FILE: arquivoResposta,
      ANTHROPIC_API_KEY: 'chave-de-teste-nao-e-real',
      BLINDAR_NO_CACHE: '1',   // senão a 2ª chamada devolve o veredito da 1ª
    },
  });
    // O nome do agente e o basename SEM `.api.sh` — `check-pentest`, nao
  // `check-pentest.api`. Trocar isso fazia o teste procurar um arquivo que
  // nunca existiu e reportar "nao gravou result" para um check que gravou.
  const rf = join(dir, '.blindar', 'results', check.replace(/\.api\.sh$/, '').replace(/\.sh$/, '') + '.json');
  let j = null;
  try { j = JSON.parse(readFileSync(rf, 'utf8')); } catch { /* sem result */ }
  // No Windows o antivírus/indexador ainda pode estar com um handle aberto logo
  // depois do check terminar; EPERM aqui derrubava o teste inteiro por causa da
  // limpeza, não do que ele mede. Falhar em apagar temporário não é falha de
  // contrato — anota e segue.
  try { rmSync(dir, { recursive: true, force: true, maxRetries: 5, retryDelay: 200 }); }
  catch { naoApagados.push(dir); }
  return { j, rc: r.status, stderr: (r.stderr || '').slice(-300) };
}

let ok = 0; const falhas = [];
const anota = (cond, msg) => { if (cond) ok++; else falhas.push(msg); };

for (const ck of apiChecks) {
  // 1) findings com crit → failed, e os findings CHEGAM (não vazios, não trocados)
  const a = roda(ck, 'com-findings');
  if (!a.j) { falhas.push(`${ck}: não gravou result (com-findings) ${a.stderr}`); continue; }
  anota(a.j.status === 'failed', `${ck}: crit deveria dar failed, deu ${a.j.status}`);
  const proprio = Boolean(respostasPorCheck[ck]);
  const f0 = (a.j.findings || [])[0] || {};
  anota(/credencial em texto claro/.test(f0.message || ''),
    `${ck}: mensagem do finding perdida ou trocada → ${JSON.stringify(f0.message)}`);
  if (!proprio) {
    // Só quem usa o formato comum tem 2 findings e file/line: o
    // proactive-analysis descarta severidade abaixo de high e não carrega
    // arquivo, então exigir isso dele seria testar o teste.
    anota((a.j.findings || []).length === 2,
      `${ck}: esperava 2 findings, veio ${(a.j.findings || []).length}`);
    anota(f0.file === 'src/a.js' && String(f0.line) === '12',
      `${ck}: file/line deslocados → ${JSON.stringify([f0.file, f0.line])}`);
    const f1 = (a.j.findings || [])[1] || {};
    anota(f1.severity === 'low',
      `${ck}: severidade fora do enum deveria virar low, virou ${JSON.stringify(f1.severity)}`);
  }
  // Isto vale para TODOS: severidade que o modelo inventou nunca pode entrar no
  // result fora do enum — o agregador conta por severidade, e chave desconhecida
  // não é contada por ninguém.
  for (const f of a.j.findings || []) {
    anota(['crit', 'high', 'med', 'low'].includes(f.severity),
      `${ck}: severidade "${f.severity}" fora do enum chegou ao result`);
  }

  // 2) sem findings → passed
  const b = roda(ck, 'sem-findings');
  anota(b.j && b.j.status === 'passed', `${ck}: sem findings deveria dar passed, deu ${b.j && b.j.status}`);

  // 3) resposta sem tool_use → skipped, NUNCA passed
  const c = roda(ck, 'sem-tool-use');
  anota(c.j && c.j.status === 'skipped',
    `${ck}: resposta ininterpretável deveria dar skipped, deu ${c.j && c.j.status}`);
}

try { rmSync(arquivoResposta, { force: true }); } catch {}

if (falhas.length) {
  console.error(`FALHA: ${falhas.length} de ${ok + falhas.length} asserções`);
  for (const f of falhas.slice(0, 25)) console.error('  ' + f);
  process.exit(1);
}
if (naoApagados.length) console.log(`  (${naoApagados.length} temporários não apagados — handle preso no Windows)`);
console.log(`ok — ${apiChecks.length} checks .api.sh, ${ok} asserções`);
