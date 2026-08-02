#!/usr/bin/env node
// Relatório de fases do blindar — estado persistente entre sessões.
//
// O relatório é a MEMÓRIA do hardening: cada fase roda numa sessão separada,
// sem contexto da anterior. Sem ele, a fase 15 não sabe o que a fase 2 fez.
//
// Fica em ./blindar/RELATORIO.md — pasta VISÍVEL e versionada, ao contrário de
// .blindar/, que é transitória e ignorada pelo git. O relatório é artefato de
// auditoria: some com ele e você perde o histórico do que já foi verificado.
//
// Uso:
//   node blindar-report.mjs init                      cria se não existir
//   node blindar-report.mjs status                    estado + próxima fase
//   node blindar-report.mjs set --fase 2 --estado ok --resumo "..." \
//        [--pendencia "..."] [--achado "crit: ..."]

import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const DIR = 'blindar';
const FILE = join(DIR, 'RELATORIO.md');
const MARK = 'blindar:state';

export const FASES = [
  { n: 0,  nome: 'Pré-requisitos (rg + jq + checks instalados)', opt: false },
  { n: 1,  nome: 'Baseline — grafo, stack e prova de que a app sobe', opt: false },
  { n: 2,  nome: 'Segurança aplicacional core', opt: false },
  { n: 3,  nome: 'Rede, API e contratos', opt: false },
  { n: 4,  nome: 'Frontend hardening', opt: false },
  { n: 5,  nome: 'Supply chain', opt: false },
  { n: 6,  nome: 'Banco de dados, backup e recuperação', opt: false },
  { n: 7,  nome: 'Observabilidade e ciclo de vida do log', opt: false },
  { n: 8,  nome: 'Compliance', opt: false },
  { n: 9,  nome: 'Performance', opt: false },
  { n: 10, nome: 'Fluidez, acessibilidade e SEO', opt: false },
  { n: 11, nome: 'Resiliência e escalabilidade', opt: false },
  { n: 12, nome: 'Anti-mock e externalização', opt: false },
  { n: 13, nome: 'Testes', opt: false },
  { n: 14, nome: 'DX, entrega e documentação', opt: false },
  { n: 15, nome: 'Pentest e revisão adversarial', opt: false },
  { n: 16, nome: 'Product Evolution (opcional)', opt: true },
  { n: 17, nome: 'Recon passivo externo (opcional)', opt: true },
  { n: 19, nome: 'Pentest ATIVO (opcional, exige autorização)', opt: true },
];

// Estados. 'pendencias' e 'bloqueada' são os que voltam pra lista de revisita:
// fase fechada com pendência não é fase fechada.
const ESTADOS = {
  nao_rodada: { icone: '⬜', rotulo: 'não rodada',  revisitar: false },
  ok:         { icone: '✅', rotulo: 'passou',      revisitar: false },
  pendencias: { icone: '⚠️', rotulo: 'com pendências', revisitar: true },
  bloqueada:  { icone: '❌', rotulo: 'bloqueada',   revisitar: true },
  pulada:     { icone: '⏭️', rotulo: 'não se aplica', revisitar: false },
};

const vazio = () => ({
  projeto: process.cwd().split(/[\\/]/).pop(),
  criado_em: new Date().toISOString().slice(0, 10),
  fases: Object.fromEntries(FASES.map((f) => [f.n, {
    estado: 'nao_rodada', resumo: '', pendencias: [], achados: [], atualizado_em: null,
  }])),
});

function ler() {
  if (!existsSync(FILE)) return null;
  const txt = readFileSync(FILE, 'utf8');
  const m = txt.match(new RegExp(`<!--\\s*${MARK}\\s*([\\s\\S]*?)-->`));
  if (!m) return null;
  try { return JSON.parse(m[1]); } catch { return null; }
}

function render(s) {
  const revisitar = FASES.filter((f) => ESTADOS[s.fases[f.n]?.estado]?.revisitar);
  const feitas = FASES.filter((f) => s.fases[f.n]?.estado !== 'nao_rodada');
  const prox = FASES.find((f) => !f.opt && s.fases[f.n]?.estado === 'nao_rodada');

  const linhas = [];
  linhas.push(`# Relatório blindar — ${s.projeto}`);
  linhas.push('');
  linhas.push(`Iniciado em ${s.criado_em}. Última atualização: ${new Date().toISOString().slice(0, 10)}.`);
  linhas.push('');
  linhas.push('> Este arquivo é o estado do hardening. Cada fase roda numa sessão');
  linhas.push('> separada e sem contexto da anterior — é daqui que ela descobre o que');
  linhas.push('> já foi feito. **Não apague, e commite junto com as correções.**');
  linhas.push('');
  linhas.push(`**Progresso:** ${feitas.length}/${FASES.length} fases tocadas · ` +
              `${revisitar.length} ${revisitar.length === 1 ? 'precisa' : 'precisam'} voltar`);
  linhas.push('');

  linhas.push('## Estado das fases');
  linhas.push('');
  linhas.push('| | Fase | Estado | Resumo | Atualizado |');
  linhas.push('|---|---|---|---|---|');
  for (const f of FASES) {
    const d = s.fases[f.n] || { estado: 'nao_rodada' };
    const e = ESTADOS[d.estado] || ESTADOS.nao_rodada;
    const resumo = (d.resumo || '—').replace(/\|/g, '\\|').slice(0, 90);
    linhas.push(`| ${e.icone} | **${f.n}** ${f.nome}${f.opt ? ' *(opt)*' : ''} | ${e.rotulo} | ${resumo} | ${d.atualizado_em || '—'} |`);
  }
  linhas.push('');

  if (revisitar.length) {
    linhas.push('## ⚠️ Fases que precisam voltar');
    linhas.push('');
    linhas.push('Fase fechada com pendência não é fase fechada. Estas ficam abertas:');
    linhas.push('');
    for (const f of revisitar) {
      const d = s.fases[f.n];
      linhas.push(`### Fase ${f.n} — ${f.nome}  (${ESTADOS[d.estado].rotulo})`);
      if (d.resumo) linhas.push('', d.resumo);
      if (d.pendencias?.length) {
        linhas.push('', '**Falta:**');
        d.pendencias.forEach((p) => linhas.push(`- [ ] ${p}`));
      }
      linhas.push('');
    }
  } else if (feitas.length) {
    linhas.push('## ✅ Nenhuma fase pendente de revisita');
    linhas.push('');
  }

  const comDetalhe = FASES.filter((f) => {
    const d = s.fases[f.n];
    return d && d.estado !== 'nao_rodada' && (d.resumo || d.achados?.length);
  });
  if (comDetalhe.length) {
    linhas.push('## Histórico por fase');
    linhas.push('');
    for (const f of comDetalhe) {
      const d = s.fases[f.n];
      const e = ESTADOS[d.estado];
      linhas.push(`### ${e.icone} Fase ${f.n} — ${f.nome}`);
      linhas.push('');
      linhas.push(`*${e.rotulo} · ${d.atualizado_em || 's/data'}*`);
      if (d.resumo) linhas.push('', d.resumo);
      if (d.achados?.length) {
        linhas.push('', '**Achados tratados:**');
        d.achados.forEach((a) => linhas.push(`- ${a}`));
      }
      if (d.pendencias?.length) {
        linhas.push('', '**Pendências:**');
        d.pendencias.forEach((p) => linhas.push(`- [ ] ${p}`));
      }
      linhas.push('');
    }
  }

  linhas.push('## Próximo passo');
  linhas.push('');
  if (revisitar.length) {
    linhas.push(`Voltar à fase **${revisitar[0].n}** (${revisitar[0].nome}) para fechar as pendências.`);
  } else if (prox) {
    linhas.push(`Seguir para a fase **${prox.n}** — ${prox.nome}.`);
  } else {
    linhas.push('Todas as fases obrigatórias foram fechadas. Considere as opcionais.');
  }
  linhas.push('');
  linhas.push('---');
  linhas.push('');
  linhas.push(`<!-- ${MARK}`);
  linhas.push(JSON.stringify(s, null, 2));
  linhas.push('-->');
  return linhas.join('\n') + '\n';
}

function salvar(s) {
  mkdirSync(DIR, { recursive: true });
  writeFileSync(FILE, render(s));
}

function args() {
  const a = process.argv.slice(3);
  const o = { pendencia: [], achado: [] };
  for (let i = 0; i < a.length; i++) {
    if (!a[i].startsWith('--')) continue;
    const k = a[i].slice(2);
    const v = a[i + 1] && !a[i + 1].startsWith('--') ? a[++i] : 'true';
    if (k === 'pendencia' || k === 'achado') o[k].push(v);
    else o[k] = v;
  }
  return o;
}

const cmd = process.argv[2];

if (cmd === 'init') {
  if (ler()) { console.log(`já existe: ${FILE} — leia antes de começar a fase`); process.exit(0); }
  salvar(vazio());
  console.log(`criado: ${FILE}`);
} else if (cmd === 'status') {
  const s = ler();
  if (!s) { console.log('sem relatório — rode `init` primeiro'); process.exit(0); }
  for (const f of FASES) {
    const d = s.fases[f.n] || { estado: 'nao_rodada' };
    const e = ESTADOS[d.estado] || ESTADOS.nao_rodada;
    console.log(`${e.icone} fase ${String(f.n).padStart(2)} ${e.rotulo.padEnd(16)} ${f.nome}`);
    (d.pendencias || []).forEach((p) => console.log(`      falta: ${p}`));
  }
  const rev = FASES.filter((f) => ESTADOS[s.fases[f.n]?.estado]?.revisitar);
  const prox = FASES.find((f) => !f.opt && s.fases[f.n]?.estado === 'nao_rodada');
  console.log('');
  if (rev.length) console.log(`PRECISAM VOLTAR: ${rev.map((f) => f.n).join(', ')}`);
  console.log(prox ? `PRÓXIMA: fase ${prox.n} — ${prox.nome}` : 'obrigatórias fechadas');
} else if (cmd === 'set') {
  const o = args();
  const s = ler() || vazio();
  const n = String(parseInt(o.fase, 10));
  if (!FASES.some((f) => String(f.n) === n)) { console.error(`fase inválida: ${o.fase}`); process.exit(1); }
  if (!ESTADOS[o.estado]) { console.error(`estado inválido: ${o.estado} (use ${Object.keys(ESTADOS).join('|')})`); process.exit(1); }
  s.fases[n] = {
    estado: o.estado,
    resumo: o.resumo || s.fases[n]?.resumo || '',
    pendencias: o.pendencia.length ? o.pendencia : (s.fases[n]?.pendencias || []),
    achados: o.achado.length ? o.achado : (s.fases[n]?.achados || []),
    atualizado_em: new Date().toISOString().slice(0, 10),
  };
  if (o.estado === 'ok' && !o.pendencia.length) s.fases[n].pendencias = [];
  salvar(s);
  console.log(`fase ${n} → ${ESTADOS[o.estado].icone} ${ESTADOS[o.estado].rotulo}`);
} else {
  console.log('uso: blindar-report.mjs init | status | set --fase N --estado ok|pendencias|bloqueada|pulada --resumo "..." [--pendencia "..."] [--achado "..."]');
  process.exit(1);
}
