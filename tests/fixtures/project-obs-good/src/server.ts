// FIXTURE SEGURA — comentarios neutros.
import express from 'express';
const app = express();
app.get('/healthz', (req, res) => res.json({ status: 'ok' }));
app.get('/health/ready', (req, res) => res.json({ ready: true }));
export default app;
