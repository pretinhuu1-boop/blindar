const logger = require("pino")();

async function cadastrar(req, res) {
  const usuario = await criar(req.body);
  logger.info({ evento: "usuario.criado", usuarioId: usuario.id });
  return res.json({ ok: true });
}

module.exports = { cadastrar };
