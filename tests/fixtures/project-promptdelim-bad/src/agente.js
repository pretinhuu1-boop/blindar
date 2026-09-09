const Anthropic = require("@anthropic-ai/sdk");
const client = new Anthropic();

async function classificar(mensagemDoCliente) {
  const prompt = `Voce classifica pedidos. Responda so a categoria.\n${mensagemDoCliente}`;
  return client.messages.create({
    model: "claude-sonnet-5",
    max_tokens: 64,
    messages: [{ role: "user", content: prompt }],
  });
}

module.exports = { classificar };
