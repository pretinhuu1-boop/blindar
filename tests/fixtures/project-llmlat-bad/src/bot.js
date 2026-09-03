const Anthropic = require("@anthropic-ai/sdk");
const client = new Anthropic();

async function responder(texto) {
  const r = await client.messages.create({
    model: "claude-sonnet-5",
    max_tokens: 512,
    messages: [{ role: "user", content: texto }],
  });
  return r.content[0].text;
}

module.exports = { responder };
