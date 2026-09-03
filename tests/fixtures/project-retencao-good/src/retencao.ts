import cron from "node-cron";

// Roda 3h da manha: apaga de fato o que passou de RETENCAO_DIAS.
cron.schedule("0 3 * * *", async () => {
  const limite = new Date(Date.now() - Number(process.env.RETENCAO_DIAS) * 86400000);
  await db.evento.deleteMany({ where: { createdAt: { lt: limite } } });
});
