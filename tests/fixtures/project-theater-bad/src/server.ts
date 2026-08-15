import helmet from 'helmet';
import cors from 'cors';
import https from 'node:https';

app.use(helmet({ contentSecurityPolicy: false }));
app.use(cors({ origin: true, credentials: true }));

const agent = new https.Agent({ rejectUnauthorized: false });

app.use((req, res, next) => {
  res.setHeader('Content-Security-Policy', "script-src 'self' 'unsafe-inline'");
  next();
});
