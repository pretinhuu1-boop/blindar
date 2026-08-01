// DIAGNÓSTICO OPERACIONAL — NÃO É TRILHA DE AUDITORIA.
// Estes arquivos existem pra investigar incidente e são apagados por retenção
// curta. Obrigação legal de auditoria vive em armazenamento próprio, com prazo
// próprio; apagar o que está aqui não pode ter efeito legal.
// Ver agents/log-ops-retention.md e docs/log-ops-incidente.md.

import { appendFileSync, createReadStream, createWriteStream, existsSync, mkdirSync, renameSync, statfsSync, unlinkSync } from 'node:fs';
import { createGzip } from 'node:zlib';
import { join } from 'node:path';
import { randomBytes } from 'node:crypto';

export const DEFAULT_MAX_BYTES = 16 * 1024 * 1024;

// <boot> é sorteado no boot do processo, NÃO o PID: PID é reciclado, e um
// processo que reinicia no mesmo dia pode herdar o arquivo do anterior —
// exatamente a corrupção que "um arquivo por processo" existe pra evitar.
const BOOT = randomBytes(3).toString('hex');

export function utcDay(d) {
  return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}-${String(d.getUTCDate()).padStart(2, '0')}`;
}

// '-' separa os campos do nome do arquivo, então NENHUM campo pode contê-lo.
// Nome de pod em k8s sempre tem hífen ("api-7f9d8c-x2k") e HOSTNAME em Windows
// também ("DESKTOP-QJG85H8") — sem isto o nome vira impossível de parsear.
const sanitize = (s) => String(s).replace(/[^A-Za-z0-9_.]/g, '_');

// Redação: NÃO definimos política aqui. O alvo injeta a dele. Se o projeto não
// tem política central, o agente emite achado — este default não pode virar a
// segunda política concorrendo com a existente.
const identity = (fields) => fields;

export function createLogger(opts = {}) {
  const {
    dir = process.env.LOG_DIR || './logs',
    service = 'app',
    env = process.env.NODE_ENV || 'development',
    version = '0.0.0',
    instance = process.env.HOSTNAME || 'local',
    maxBytes = DEFAULT_MAX_BYTES,
    redact = identity,
    now = () => new Date(),
    diskFree = defaultDiskFree,
    minFreeBytes = 1024 * 1024 * 1024,
    minFreeRatio = 0.10,
    stdout = (line) => process.stdout.write(line + '\n'),
    compress = true,
    maxQueue = 10000,
  } = opts;

  const inst = sanitize(instance);
  const streams = new Map(); // stream → { day, seq, bytes, path }
  let queue = [];
  let fileSink = true;
  let dropped = 0;
  let diskWarned = false;

  const pathFor = (day, stream, seq) =>
    join(dir, day, `${stream}-${inst}-${BOOT}-${String(seq).padStart(3, '0')}.jsonl`);

  function open(stream, day, seq) {
    mkdirSync(join(dir, day), { recursive: true, mode: 0o750 });
    return { day, seq, bytes: 0, path: pathFor(day, stream, seq) };
  }

  function slot(stream, day) {
    let s = streams.get(stream);
    if (!s) {
      s = open(stream, day, 0);
      streams.set(stream, s);
    } else if (s.day !== day) {
      // Virada do dia: fecha o arquivo anterior e recomeça a sequência.
      if (compress) gzipAsync(s.path);
      s = open(stream, day, 0);
      streams.set(stream, s);
    }
    return s;
  }

  function write(stream, day, line) {
    const s = slot(stream, day);
    const size = Buffer.byteLength(line) + 1;
    if (s.bytes > 0 && s.bytes + size > maxBytes) {
      if (compress) gzipAsync(s.path);
      const next = open(stream, s.day, s.seq + 1);
      streams.set(stream, next);
      return writeTo(next, line, size);
    }
    return writeTo(s, line, size);
  }

  function writeTo(s, line, size) {
    appendFileSync(s.path, line + '\n', { mode: 0o640 });
    s.bytes += size;
  }

  function checkDisk() {
    const info = diskFree(dir);
    if (!info) return;
    const low = info.free < minFreeBytes || (info.total > 0 && info.free / info.total < minFreeRatio);
    if (low && fileSink) {
      fileSink = false;
      if (!diskWarned) {
        diskWarned = true;
        // Grita no stdout, que continua vivo. Log não pode causar o incidente.
        stdout(JSON.stringify({
          ts: now().toISOString(), level: 'error', event: 'log.file_sink.disabled',
          service, env, instance: inst, reason: 'disk_low', free: info.free, total: info.total,
        }));
      }
    } else if (!low && !fileSink) {
      fileSink = true;
      diskWarned = false;
    }
  }

  // Caminho quente: monta o envelope, escreve no stdout e empilha. Nunca disco.
  const log = (stream, event, fields = {}) => {
    const { level = 'info', ...rest } = fields;
    const d = now();
    const rec = {
      ts: d.toISOString(), level, event, service, env,
      instance: inst, version, ...redact(rest),
    };
    const line = JSON.stringify(rec);
    stdout(line); // stdout SEMPRE — o arquivo não substitui, coexiste
    if (!fileSink || queue.length >= maxQueue) { dropped += 1; return; }
    queue.push([stream, utcDay(d), line]);
  };

  log.flush = () => {
    checkDisk();
    if (!fileSink) { dropped += queue.length; queue = []; return; }
    const batch = queue;
    queue = [];
    for (const [stream, day, line] of batch) {
      try { write(stream, day, line); } catch { dropped += 1; }
    }
  };
  log.stats = () => ({ dropped, fileSink, queued: queue.length, boot: BOOT });

  return log;
}

function gzipAsync(path) {
  if (!path || !existsSync(path)) return;
  try {
    const tmp = `${path}.gz.tmp`;
    const out = createWriteStream(tmp);
    createReadStream(path).pipe(createGzip()).pipe(out);
    out.on('finish', () => {
      try { renameSync(tmp, `${path}.gz`); unlinkSync(path); } catch { /* best-effort */ }
    });
    out.on('error', () => {});
  } catch { /* compressão é best-effort, nunca derruba a app */ }
}

function defaultDiskFree(dir) {
  try {
    const st = statfsSync(dir);
    return { free: st.bfree * st.bsize, total: st.blocks * st.bsize };
  } catch { return null; }
}
