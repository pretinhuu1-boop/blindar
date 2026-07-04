// FIXTURE SEGURA — comentarios neutros.
import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import rateLimit from 'express-rate-limit';
const app = express();
app.use(helmet());
app.use(cors({ origin: 'https://app.example.com', credentials: true }));
const limiter = rateLimit({ windowMs: 60000, max: 5 });
app.post('/api/login', limiter, (req, res) => res.json({ ok: true }));
export default app;
