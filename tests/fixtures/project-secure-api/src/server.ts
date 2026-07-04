// FIXTURE SEGURA — deve PASSAR cors-csrf, rate-limit, headers-security.
import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import rateLimit from 'express-rate-limit';
const app = express();
app.use(helmet());                                             // headers-security pass
app.use(cors({ origin: 'https://app.example.com', credentials: true }));
const limiter = rateLimit({ windowMs: 60000, max: 5 });        // rate-limit pass
app.post('/api/login', limiter, (req, res) => res.json({ ok: true }));
export default app;
