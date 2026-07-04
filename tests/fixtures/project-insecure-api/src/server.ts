// FIXTURE VULNERAVEL — comentarios neutros pra nao contaminar os checks.
import express from 'express';
import cors from 'cors';
const app = express();
app.use(cors({ origin: '*', credentials: true }));
app.post('/api/login', (req, res) => res.json({ ok: true }));
app.put('/api/user/:id', (req, res) => res.json({}));
app.delete('/api/user/:id', (req, res) => res.json({}));
app.get('/api/order/:id', (req, res) => {
  const order = orders.find((o) => o.id === req.params.id);
  res.json(order);
});
export default app;
