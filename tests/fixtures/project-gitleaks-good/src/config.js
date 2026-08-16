// FIXTURE LIMPO — mesma forma do bad, sem segredo: tudo vem do ambiente.
// Se o check disparar aqui, é falso positivo.
export const token  = process.env.AUTH_TOKEN;
export const apiKey = process.env.API_KEY;
if (!token || !apiKey) throw new Error("AUTH_TOKEN e API_KEY são obrigatórios");
