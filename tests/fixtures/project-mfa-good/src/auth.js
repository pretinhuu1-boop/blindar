const bcrypt = require("bcrypt");
const { authenticator } = require("otplib");

async function login(email, senha, codigoTotp) {
  const u = await db.user.findUnique({ where: { email } });
  if (!u || !(await bcrypt.compare(senha, u.hash))) return null;
  if (u.mfa_enabled && !authenticator.check(codigoTotp, u.totp_secret)) return null;
  return criarSessao(u);
}

module.exports = { login };
