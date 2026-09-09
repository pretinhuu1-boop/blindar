const OpenAI = require("openai");
const client = new OpenAI();

// Cota por loja: uma origem nao gasta o orcamento das outras.
async function responder(lojaId, texto) {
  const usage_limit = await db.cota.findUnique({ where: { lojaId } });
  if (usage_limit.consumo_mensal >= usage_limit.teto) {
    throw new Error("cota mensal da loja esgotada");
  }
  const r = await client.chat.completions.create({
    model: "gpt-4o-mini",
    messages: [{ role: "user", content: texto }],
  });
  await db.cota.update({ where: { lojaId }, data: { consumo_mensal: { increment: 1 } } });
  return r;
}

module.exports = { responder };
