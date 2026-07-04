// FIXTURE VULNERÁVEL — deve FALHAR cors-csrf, rate-limit, headers-security.
import express from 'express';
import cors from 'cors';
const app = express();
app.use(cors({ origin: '*', credentials: true }));   // cors-csrf CRIT
app.post('/api/login', (req, res) => res.json({ ok: true }));  // rate-limit: rota sem RL
app.put('/api/user/:id', (req, res) => res.json({}));
app.delete('/api/user/:id', (req, res) => res.json({}));
// sem helmet, sem headers de segurança → headers-security fail
export default app;
