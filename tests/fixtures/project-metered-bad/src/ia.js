const OpenAI = require("openai");
const client = new OpenAI();

async function responder(lojaId, texto) {
  return client.chat.completions.create({
    model: "gpt-4o-mini",
    messages: [{ role: "user", content: texto }],
  });
}

module.exports = { responder };
