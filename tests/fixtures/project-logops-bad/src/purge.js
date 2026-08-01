// FIXTURE VULNERÁVEL — apaga diretório sem NENHUMA guarda:
// sem regex de data no basename, sem realpath, sem checagem de symlink.
const fs = require('fs');
const path = require('path');

function purgeOld(baseDir, keepDays) {
  for (const name of fs.readdirSync(baseDir)) {
    const p = path.join(baseDir, name);
    const age = (Date.now() - fs.statSync(p).mtimeMs) / 86400000;
    if (age > keepDays) {
      fs.rmSync(p, { recursive: true, force: true });
    }
  }
}

module.exports = { purgeOld };
