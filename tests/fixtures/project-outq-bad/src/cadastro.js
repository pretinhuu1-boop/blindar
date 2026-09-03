const router = require("express").Router();
const nodemailer = require("nodemailer");

router.post("/cadastro", async (req, res) => {
  const u = await db.user.create({ data: req.body });
  await nodemailer.createTransport(cfg).sendMail({ to: u.email, subject: "Bem-vindo" });
  res.json(u);
});

module.exports = router;
