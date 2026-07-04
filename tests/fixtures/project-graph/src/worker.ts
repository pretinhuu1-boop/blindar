// FIXTURE GRAFO — worker de fila.
import { Worker } from 'bullmq';
const w = new Worker('emails', async (job) => job.data, { connection: {} });
export default w;
