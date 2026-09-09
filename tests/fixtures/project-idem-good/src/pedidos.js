const router = require("express").Router();

router.post("/pedidos", async (req, res) => {
  const idempotencyKey = req.get("Idempotency-Key");
  if (!idempotencyKey) return res.status(400).json({ erro: "Idempotency-Key obrigatorio" });

  const anterior = await db.idempotencia.findUnique({ where: { idempotencyKey } });
  if (anterior) return res.json(anterior.resposta);

  const pedido = await db.pedido.create({ data: req.body });
  await cobrar(pedido);
  await db.idempotencia.create({ data: { idempotencyKey, resposta: pedido } });
  res.json(pedido);
});

module.exports = router;
