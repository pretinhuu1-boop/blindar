// FIXTURE LIMPA — pasta por dia UTC, rotação por tamanho, um arquivo por
// processo, escrita em lote fora do caminho quente, guarda de disco cheio.
// DIAGNÓSTICO OPERACIONAL — não é trilha de auditoria.
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const LOG_DIR = process.env.LOG_DIR || 'logs';
const maxBytes = 16 * 1024 * 1024;
const BOOT = crypto.randomBytes(3).toString('hex');
const inst = String(process.env.HOSTNAME || 'local').replace(/[^A-Za-z0-9_.]/g, '_');

let queue = [];
let fileSink = true;
const state = new Map();

function utcDay(d) {
  return d.toISOString().slice(0, 10);
}

// Caminho quente: só empilha e escreve no stdout. Nunca toca disco.
function log(stream, event, fields) {
  const line = JSON.stringify({ ts: new Date().toISOString(), event, ...fields });
  process.stdout.write(line + '\n');
  if (fileSink && queue.length < 10000) queue.push([stream, line]);
}

// Guarda de disco cheio: desliga o sink de arquivo, mantém stdout, avisa.
function diskOk() {
  try {
    const st = fs.statfsSync(LOG_DIR);
    return st.bfree * st.bsize > 1024 * 1024 * 1024;
  } catch (e) {
    return true;
  }
}

function flush() {
  if (!diskOk()) { fileSink = false; queue = []; return; }
  const batch = queue;
  queue = [];
  for (const [stream, line] of batch) {
    const day = utcDay(new Date());
    const dir = path.join(LOG_DIR, day);
    fs.mkdirSync(dir, { recursive: true, mode: 0o750 });
    let s = state.get(stream);
    if (!s || s.day !== day) { s = { day: day, seq: 0, bytes: 0 }; state.set(stream, s); }
    if (s.bytes > 0 && s.bytes + line.length > maxBytes) { s.seq += 1; s.bytes = 0; }
    const file = path.join(dir, stream + '-' + inst + '-' + BOOT + '-' + String(s.seq).padStart(3, '0') + '.jsonl');
    fs.appendFileSync(file, batch.length ? line + '\n' : '', { mode: 0o640 });
    s.bytes += line.length + 1;
  }
}

setInterval(flush, 1000).unref();

module.exports = { log: log, flush: flush };
