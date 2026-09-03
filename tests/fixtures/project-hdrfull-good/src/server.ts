import express from "express";
import helmet from "helmet";

const app = express();
app.use(helmet({
  crossOriginOpenerPolicy: { policy: "same-origin" },
  crossOriginEmbedderPolicy: { policy: "require-corp" },
  crossOriginResourcePolicy: { policy: "same-site" },
}));
app.use((req, res, next) => {
  res.setHeader("Permissions-Policy", "camera=(), microphone=(), geolocation=(), payment=()");
  next();
});
app.listen(3000);
