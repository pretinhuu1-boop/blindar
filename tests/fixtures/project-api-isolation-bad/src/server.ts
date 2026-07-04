// FIXTURE VULNERAVEL — comentarios neutros.
import express from 'express';
const app = express();
app.post('/api/orders', (req, res) => res.json(req.body));
export default app;
