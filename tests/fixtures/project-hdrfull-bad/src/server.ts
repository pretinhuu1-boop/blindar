import express from "express";
import helmet from "helmet";

const app = express();
app.use(helmet());
app.listen(3000);
