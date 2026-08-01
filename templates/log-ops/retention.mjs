// DIAGNÓSTICO OPERACIONAL — NÃO É TRILHA DE AUDITORIA. Ver logger.mjs.
//
// O código que apaga é o mais perigoso do módulo. As cinco guardas abaixo não
// são opcionais:
//   1. regex EXATA no basename (não startswith, não glob)
//   2. realpath resolvido e confirmado dentro de LOG_DIR
//   3. lstat: symlink nunca é seguido nem apagado através
//   4. piso rígido: hoje e ontem nunca são apagados, comparando a DATA DO NOME,
//      não aritmética sobre mtime — se N vier 0 ou negativo, o piso segura
//   5. registra bytes liberados

import { lstatSync, mkdirSync, readdirSync, realpathSync, rmdirSync, statSync, unlinkSync, existsSync, rmSync } from 'node:fs';
import { basename, join } from 'node:path';

const DAY_RE = /^\d{4}-\d{2}-\d{2}$/;                          // guarda 1
const MS_DAY = 86400000;

export const DEFAULT_RETENTION = {
  access: 2, app: 3, error: 14, security: 30, default: 3,
};

export function retentionFromEnv(env = process.env) {
  const n = (v, d) => {
    const x = parseInt(v ?? '', 10);
    return Number.isFinite(x) && x >= 0 ? x : d;
  };
  const g = env.LOG_RETENTION_DAYS;
  const base = g ? n(g, DEFAULT_RETENTION.default) : null;
  return {
    access:   n(env.LOG_RETENTION_ACCESS_DAYS,   base ?? DEFAULT_RETENTION.access),
    app:      n(env.LOG_RETENTION_APP_DAYS,      base ?? DEFAULT_RETENTION.app),
    error:    n(env.LOG_RETENTION_ERROR_DAYS,    base ?? DEFAULT_RETENTION.error),
    security: n(env.LOG_RETENTION_SECURITY_DAYS, base ?? DEFAULT_RETENTION.security),
    default:  base ?? DEFAULT_RETENTION.default,
  };
}

const dayStr = (d) =>
  `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}-${String(d.getUTCDate()).padStart(2, '0')}`;

// Stream = prefixo antes do primeiro '-'. "job.queue-host-ab12-000.jsonl" → "job.queue"
export function streamOf(file) {
  const i = file.indexOf('-');
  return i === -1 ? file : file.slice(0, i);
}

function ageInDays(name, today) {
  const [y, m, d] = name.split('-').map(Number);
  return Math.floor((Date.UTC(today.getUTCFullYear(), today.getUTCMonth(), today.getUTCDate()) - Date.UTC(y, m - 1, d)) / MS_DAY);
}

export function sweep({ dir, retention = DEFAULT_RETENTION, now = () => new Date(), onEvent } = {}) {
  const result = { removedDirs: [], removedFiles: [], bytesFreed: 0, skipped: [] };
  if (!dir || !existsSync(dir)) return result;

  let root;
  try { root = realpathSync(dir); } catch { return result; }

  const today = now();
  const todayStr = dayStr(today);
  const yesterdayStr = dayStr(new Date(today.getTime() - MS_DAY));

  let entries;
  try { entries = readdirSync(root); } catch { return result; }

  for (const name of entries) {
    if (!DAY_RE.test(name)) { result.skipped.push([name, 'nome-nao-e-data']); continue; }      // 1
    if (name === todayStr || name === yesterdayStr) { result.skipped.push([name, 'piso']); continue; } // 4

    const p = join(root, name);

    let st;
    try { st = lstatSync(p); } catch { continue; }
    if (st.isSymbolicLink()) { result.skipped.push([name, 'symlink']); continue; }             // 3
    if (!st.isDirectory()) { result.skipped.push([name, 'nao-e-dir']); continue; }

    let real;
    try { real = realpathSync(p); } catch { continue; }
    if (real !== join(root, name) || !isInside(root, real)) {                                  // 2
      result.skipped.push([name, 'fora-do-log-dir']); continue;
    }

    const age = ageInDays(name, today);
    if (!Number.isFinite(age) || age < 2) { result.skipped.push([name, 'piso']); continue; }   // 4 (redundante de propósito)

    sweepDay(real, name, age, retention, result);
  }

  if (onEvent) {
    onEvent('log.retention.swept', {
      dirs_removed: result.removedDirs.length,
      files_removed: result.removedFiles.length,
      bytes_freed: result.bytesFreed,                                                          // 5
    });
  }
  return result;
}

// Dentro de um dia elegível, cada stream expira no SEU prazo. O diretório só
// some quando o último arquivo dele expirou — é isso que permite security
// sobreviver 30 dias enquanto access morre em 2.
function sweepDay(dirPath, name, age, retention, result) {
  let files;
  try { files = readdirSync(dirPath); } catch { return; }

  let remaining = 0;
  for (const f of files) {
    const fp = join(dirPath, f);
    let fst;
    try { fst = lstatSync(fp); } catch { continue; }
    if (fst.isSymbolicLink()) { result.skipped.push([`${name}/${f}`, 'symlink']); remaining += 1; continue; }
    if (!fst.isFile()) { remaining += 1; continue; }

    const stream = streamOf(f);
    const keep = retention[stream] ?? retention.default;
    if (age > keep) {
      try {
        const size = fst.size;
        unlinkSync(fp);
        result.removedFiles.push(`${name}/${f}`);
        result.bytesFreed += size;
      } catch { remaining += 1; }
    } else {
      remaining += 1;
    }
  }

  if (remaining === 0) {
    try { rmdirSync(dirPath); result.removedDirs.push(name); } catch { /* não vazio: fica */ }
  }
}

function isInside(root, p) {
  const r = root.endsWith(sep()) ? root : root + sep();
  return p === root || p.startsWith(r);
}
const sep = () => (process.platform === 'win32' ? '\\' : '/');

// Lock advisory: com um arquivo por processo há muitos processos; só um varre.
// mkdir é atômico nos dois SOs. Lock mais velho que staleMs é assumido órfão.
export function withSweepLock(dir, fn, { staleMs = 3600000, now = () => Date.now() } = {}) {
  const lock = join(dir, '.sweep.lock');
  try {
    mkdirSync(lock);
  } catch {
    try {
      if (now() - statSync(lock).mtimeMs < staleMs) return null;
      rmSync(lock, { recursive: true, force: true });
      mkdirSync(lock);
    } catch { return null; }
  }
  try { return fn(); } finally { try { rmSync(lock, { recursive: true, force: true }); } catch {} }
}
