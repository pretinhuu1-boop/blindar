const express = require("express");
const app = express();

// Kill switch: lido a cada requisicao, muda sem deploy.
function ligado(nome) {
  if (nome === "NOVO_CHECKOUT") return process.env.FEATURE_NOVO_CHECKOUT === "on";
  return false;
}

app.get("/checkout", (req, res) => {
  res.json({ fluxo: ligado("NOVO_CHECKOUT") ? "novo" : "antigo" });
});

app.listen(3000);
