const { Worker } = require("bullmq");
const nodemailer = require("nodemailer");

new Worker("email", async (job) => {
  const u = await db.user.findUnique({ where: { id: job.data.userId } });
  await nodemailer.createTransport(cfg).sendMail({ to: u.email, subject: "Bem-vindo" });
});
