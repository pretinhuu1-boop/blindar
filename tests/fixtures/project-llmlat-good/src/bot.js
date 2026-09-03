const Anthropic = require("@anthropic-ai/sdk");
const logger = require("pino")();
const client = new Anthropic();

async function responder(texto) {
  const inicio = Date.now();
  let resultado = "ok";
  try {
    const r = await client.messages.create({
      model: "claude-sonnet-5",
      max_tokens: 512,
      messages: [{ role: "user", content: texto }],
    });
    return r.content[0].text;
  } catch (e) {
    resultado = "erro";
    throw e;
  } finally {
    logger.info({ evento: "llm.chamada", modelo: "claude-sonnet-5", resultado, duration_ms: Date.now() - inicio });
  }
}

module.exports = { responder };
