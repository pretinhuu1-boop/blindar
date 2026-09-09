const express = require("express");
const client = require("prom-client");
const app = express();
client.collectDefaultMetrics();
app.get("/metrics", async (req, res) => res.send(await client.register.metrics()));
app.get("/healthz", (req, res) => res.send("ok"));
app.listen(3000);
