// FIXTURE LIMPA — varredor com as guardas obrigatórias:
//   1. regex EXATA de data no basename
//   2. realpath resolvido e confirmado dentro do LOG_DIR
//   3. lstat: symlink nunca seguido nem apagado através
//   4. piso rígido: hoje e ontem nunca são apagados
//   5. registra bytes liberados
const fs = require('fs');
const path = require('path');

const DAY_RE = /^\d{4}-\d{2}-\d{2}$/;
const RETENTION = { access: 2, app: 3, error: 14, security: 30, default: 3 };

function dayStr(d) { return d.toISOString().slice(0, 10); }

function sweep(logDir, now) {
  const root = fs.realpathSync(logDir);
  const today = dayStr(now);
  const yesterday = dayStr(new Date(now.getTime() - 86400000));
  let bytesFreed = 0;

  for (const name of fs.readdirSync(root)) {
    if (!DAY_RE.test(name)) continue;                       // guarda 1
    if (name === today || name === yesterday) continue;     // guarda 4

    const p = path.join(root, name);
    const st = fs.lstatSync(p);
    if (st.isSymbolicLink() || !st.isDirectory()) continue; // guarda 3
    if (fs.realpathSync(p).indexOf(root) !== 0) continue;   // guarda 2

    const age = Math.floor((new Date(today) - new Date(name)) / 86400000);
    for (const f of fs.readdirSync(p)) {
      const stream = f.split('-')[0];
      const keep = RETENTION[stream] || RETENTION.default;
      if (age > keep) {
        const fp = path.join(p, f);
        bytesFreed += fs.lstatSync(fp).size;
        fs.unlinkSync(fp);
      }
    }
    if (fs.readdirSync(p).length === 0) fs.rmSync(p, { recursive: true, force: true });
  }
  return bytesFreed;                                        // guarda 5
}

module.exports = { sweep: sweep, RETENTION: RETENTION };
