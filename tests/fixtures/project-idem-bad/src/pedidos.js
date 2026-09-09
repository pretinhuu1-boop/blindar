const router = require("express").Router();

router.post("/pedidos", async (req, res) => {
  const pedido = await db.pedido.create({ data: req.body });
  await cobrar(pedido);
  res.json(pedido);
});

module.exports = router;
