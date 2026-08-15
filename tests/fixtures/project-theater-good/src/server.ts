import helmet from 'helmet';
import cors from 'cors';
import https from 'node:https';

const ALLOWED = ['https://app.exemplo.com', 'https://admin.exemplo.com'];

app.use(helmet());
app.use(cors({ origin: ALLOWED, credentials: true }));

const agent = new https.Agent({ keepAlive: true });

app.use((req, res, next) => {
  res.setHeader('Content-Security-Policy', "script-src 'self'; object-src 'none'");
  next();
});
