// FIXTURE VULNERAVEL — comentarios neutros.
import OpenAI from 'openai';
const client = new OpenAI();
const SYSTEM_PROMPT = 'voce e um assistente';
export async function ask(userInput: string) {
  const prompt = `${SYSTEM_PROMPT}\n${userInput}`;
  return client.chat.completions.create({ messages: [{ role: 'user', content: prompt }] });
}
