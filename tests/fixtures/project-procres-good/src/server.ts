// FIXTURE SEGURA — graceful shutdown + health live/ready.
import express from 'express';
const app = express();
app.get('/health/live', (req, res) => res.json({ live: true }));
app.get('/health/ready', (req, res) => res.json({ ready: true }));
const server = app.listen(3000);
process.on('SIGTERM', () => server.close());
export default app;
