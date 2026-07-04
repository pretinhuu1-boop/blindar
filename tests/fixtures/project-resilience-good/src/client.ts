// FIXTURE BOA — timeout + circuit breaker + retry com backoff.
import CircuitBreaker from 'opossum';
import pRetry from 'p-retry';
async function call(id: string) {
  return fetch(`https://api.example.com/users/${id}`, { signal: AbortSignal.timeout(5000) });
}
const breaker = new CircuitBreaker(call, { timeout: 6000 });
export const getUser = (id: string) => pRetry(() => breaker.fire(id), { retries: 3 });
