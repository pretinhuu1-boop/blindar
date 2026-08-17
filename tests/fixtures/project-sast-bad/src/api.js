// FIXTURE VULNERAVEL — padroes que o SAST DEVE achar.
// Nao sao regex de palavra: sao fluxo de dado do request ate o sink.
const app = require('express')();

// input do usuario direto num eval
app.get('/exec', (req, res) => {
  eval(req.query.cmd);
  res.send('ok');
});

// input do usuario concatenado em query SQL
app.get('/users/:id', (req, res) => {
  db.query('SELECT * FROM users WHERE id = ' + req.params.id, (e, r) => res.json(r));
});

module.exports = app;
