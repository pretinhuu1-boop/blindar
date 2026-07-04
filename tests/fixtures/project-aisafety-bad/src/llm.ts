// FIXTURE VULNERAVEL — executa a saida do modelo (RCE).
import { openai } from './client';
export async function run(prompt: string) {
  const completionText = await openai.generate(prompt);
  return eval(completionText);
}
