// FIXTURE SEGURA — comentarios neutros.
import OpenAI from 'openai';
const client = new OpenAI();
const SYSTEM_PROMPT = 'voce e um assistente';
export async function ask(userInput: string) {
  return client.chat.completions.create({
    max_tokens: 500,
    messages: [
      { role: 'system', content: SYSTEM_PROMPT },
      { role: 'user', content: userInput },
    ],
  });
}
