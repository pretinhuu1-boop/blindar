// FIXTURE SEGURA — roles separados, max_tokens, rate limit.
import { openai } from './client';
import rateLimit from 'express-rate-limit';
export const limiter = rateLimit({ windowMs: 60000, max: 10 });
export function ask(userInput: string) {
  return openai.chat.completions.create({
    max_tokens: 500,
    messages: [
      { role: 'system', content: 'You are helpful' },
      { role: 'user', content: userInput },
    ],
  });
}
