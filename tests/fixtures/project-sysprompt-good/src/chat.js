// FIXTURE SEGURA — system prompt fica no servidor, nunca exposto nem logado.
const SYSTEM_PROMPT = 'You are a support agent. Follow internal policy doc 42.';

export function chat(req, res) {
  const answer = callModel(SYSTEM_PROMPT, req.body.question);
  // devolve só a resposta ao usuario — prompt permanece interno
  res.json({ answer });
}

function callModel(prompt, question) {
  return 'stub';
}
