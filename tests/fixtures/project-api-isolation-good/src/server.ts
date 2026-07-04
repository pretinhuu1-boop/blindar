// FIXTURE SEGURA — comentarios neutros.
import express from 'express';
import helmet from 'helmet';
import rateLimit from 'express-rate-limit';
import { z } from 'zod';
const app = express();
app.use(helmet());
app.use(rateLimit({ windowMs: 60000, max: 100 }));
const orderSchema = z.object({ item: z.string() });
app.post('/api/orders', (req, res) => {
  const data = orderSchema.parse(req.body);
  res.json(data);
});
export default app;
