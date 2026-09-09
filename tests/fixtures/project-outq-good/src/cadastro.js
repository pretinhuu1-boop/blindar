const router = require("express").Router();
const { Queue } = require("bullmq");
const filaEmail = new Queue("email");

router.post("/cadastro", async (req, res) => {
  const u = await db.user.create({ data: req.body });
  await filaEmail.add("boas-vindas", { userId: u.id }, { attempts: 5, backoff: { type: "exponential", delay: 2000 } });
  res.json(u);
});

module.exports = router;
