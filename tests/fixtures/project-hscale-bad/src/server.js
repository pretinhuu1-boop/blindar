// FIXTURE VULNERAVEL — tudo aqui funciona com UMA replica e quebra com DUAS.
import express from 'express';
import session from 'express-session';
import rateLimit from 'express-rate-limit';
import multer from 'multer';
import { Server } from 'socket.io';
import Stripe from 'stripe';

const app = express();

// 6. lista de revogacao de token no processo: a outra replica nao sabe que
//    o token foi revogado e continua aceitando ate expirar
const revokedTokens = new Set();
export const revogar = (t) => revokedTokens.add(t);
export const foiRevogado = (t) => revokedTokens.has(t);

// 1. sessao no MemoryStore: some quando o balanceador manda pra outra instancia
app.use(session({ secret: process.env.SESSION_SECRET, resave: false, saveUninitialized: false }));

// 2. rate limit contado na memoria do processo: limite efetivo vira N x o configurado
app.use(rateLimit({ windowMs: 60000, max: 100 }));

// 3. upload em disco local: o GET seguinte cai na outra replica e da 404
const upload = multer({ dest: './uploads' });
app.post('/arquivos', upload.single('f'), (req, res) => res.json({ ok: true }));

// 4. webhook processa toda entrega: o reenvio do provedor credita de novo
const stripe = new Stripe(process.env.STRIPE_KEY);
app.post('/webhook', (req, res) => {
  const evento = stripe.webhooks.constructEvent(req.body, req.headers['stripe-signature'], process.env.WH_SECRET);
  creditar(evento.data.object.amount);
  res.json({ recebido: true });
});

// 5. socket.io sem adapter: broadcast so alcanca quem esta nesta instancia
const io = new Server(app.listen(3000));
io.on('connection', (s) => s.on('msg', (m) => io.emit('msg', m)));
