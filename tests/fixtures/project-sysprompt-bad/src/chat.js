// FIXTURE VULNERAVEL — LLM07 system prompt leakage.
const SYSTEM_PROMPT = 'You are a support agent. Follow internal policy doc 42.';

export function debugChat(req, res) {
  console.log('using prompt:', SYSTEM_PROMPT); // vaza pro log
  // devolve o system prompt ao cliente — expõe instrucoes internas
  res.json({ answer: 'ok', systemPrompt: SYSTEM_PROMPT });
}
