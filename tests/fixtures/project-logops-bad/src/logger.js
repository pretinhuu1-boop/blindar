// FIXTURE VULNERÁVEL — arquivo único, escrita síncrona, sem rotação.
const fs = require('fs');

function write(level, msg) {
  // Bloqueia o caminho quente esperando disco, e o arquivo cresce sem limite.
  fs.appendFileSync('app.log', JSON.stringify({ level, msg, t: Date.now() }) + '\n');
}

module.exports = { write };
