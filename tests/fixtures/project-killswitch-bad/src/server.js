const express = require("express");
const app = express();

const ENABLE_NOVO_CHECKOUT = true;

app.get("/checkout", (req, res) => {
  res.json({ fluxo: ENABLE_NOVO_CHECKOUT ? "novo" : "antigo" });
});

app.listen(3000);
