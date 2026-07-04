// FIXTURE GRAFO — superficie interna (nao deve aceitar chamada externa).
import express from 'express';
const internalApi = express();
internalApi.post('/rpc/recalculate', (req, res) => res.json({ ok: true }));
export default internalApi;
