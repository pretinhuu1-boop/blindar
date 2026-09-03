const bcrypt = require("bcrypt");

async function login(email, senha) {
  const u = await db.user.findUnique({ where: { email } });
  if (!u || !(await bcrypt.compare(senha, u.hash))) return null;
  return criarSessao(u);
}

module.exports = { login };
