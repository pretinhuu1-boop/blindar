// FIXTURE GRAFO — superficie externa (API publica).
import express from 'express';
const app = express();
app.get('/api/products', (req, res) => res.json([]));
app.post('/api/orders', (req, res) => res.json({}));
export default app;
