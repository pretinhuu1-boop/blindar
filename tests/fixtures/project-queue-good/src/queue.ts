// FIXTURE BOA — trabalho enfileirado com retry, DLQ e idempotencia.
import { Queue } from 'bullmq';
export const emailQueue = new Queue('emails', {
  defaultJobOptions: {
    attempts: 3,
    backoff: { type: 'exponential', delay: 1000 },
    removeOnFail: false,
  },
});
export async function onSignup(to: string) {
  await emailQueue.add('welcome', { to }, { jobId: `welcome:${to}` });
}
