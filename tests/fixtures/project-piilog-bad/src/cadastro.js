const logger = require("pino")();

async function cadastrar(req, res) {
  logger.info(req.body);
  console.log("novo usuario cpf=", req.body.cpf, "telefone=", req.body.telefone);
  logger.debug("auth header", req.headers.authorization);
  return res.json({ ok: true });
}

module.exports = { cadastrar };
