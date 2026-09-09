const express = require("express");
const app = express();
app.get("/", (req, res) => res.send("ok"));

const server = app.listen(3000);

// Para de aceitar conexao nova, termina o que esta em voo, fecha o pool, sai.
async function encerrar() {
  server.close(async () => {
    await prisma.$disconnect();
    await fila.close();
    process.exit(0);
  });
}
process.on("SIGTERM", encerrar);
process.on("SIGINT", encerrar);
