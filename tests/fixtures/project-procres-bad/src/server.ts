// FIXTURE VULNERAVEL — sem SIGTERM, sem health.
import express from 'express';
const app = express();
app.get('/', (req, res) => res.send('hi'));
app.listen(3000);
export default app;
