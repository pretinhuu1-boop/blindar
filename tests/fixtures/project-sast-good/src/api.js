// FIXTURE LIMPO — mesma forma, sem o fluxo perigoso.
const app = require('express')();

// nada de eval: mapa fechado de operacoes permitidas
const OPERACOES = { ping: () => 'pong', versao: () => '1.0.0' };
app.get('/exec', (req, res) => {
  const op = OPERACOES[req.query.cmd];
  if (!op) return res.status(400).json({ erro: 'operacao desconhecida' });
  res.json({ resultado: op() });
});

// query parametrizada: o valor nunca vira parte do SQL
app.get('/users/:id', (req, res) => {
  db.query('SELECT * FROM users WHERE id = ?', [req.params.id], (e, r) => res.json(r));
});

module.exports = app;
