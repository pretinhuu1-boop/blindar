// FIXTURE LIMPO — mesma aplicacao, preparada para N replicas.
import express from 'express';
import session from 'express-session';
import RedisStore from 'connect-redis';
import rateLimit from 'express-rate-limit';
import RedisStoreRL from 'rate-limit-redis';
import { Server } from 'socket.io';
import { createAdapter } from '@socket.io/redis-adapter';
import { S3Client } from '@aws-sdk/client-s3';
import Stripe from 'stripe';
import { redis, pub, sub } from './redis.js';

const app = express();

// 1. sessao em store compartilhado
app.use(session({ store: new RedisStore({ client: redis }), secret: process.env.SESSION_SECRET,
                  resave: false, saveUninitialized: false }));

// 2. rate limit com contagem compartilhada
app.use(rateLimit({ windowMs: 60000, max: 100,
                    store: new RedisStoreRL({ sendCommand: (...a) => redis.sendCommand(a) }) }));

// 3. upload por presigned URL no S3 — nenhuma replica guarda arquivo
const s3 = new S3Client({ region: process.env.AWS_REGION });
app.post('/arquivos/url', async (req, res) => res.json({ url: await gerarPresigned(s3, req.body.nome) }));

// 4. webhook idempotente: o mesmo event.id nunca e processado duas vezes
const stripe = new Stripe(process.env.STRIPE_KEY);
app.post('/webhook', async (req, res) => {
  const evento = stripe.webhooks.constructEvent(req.body, req.headers['stripe-signature'], process.env.WH_SECRET);
  const novo = await redis.set(`idempotencia:${evento.id}`, '1', { NX: true, EX: 86400 });
  if (!novo) return res.json({ recebido: true, jaProcessado: true });
  await creditar(evento.data.object.amount);
  res.json({ recebido: true });
});

// 5. socket.io com adapter Redis: broadcast alcanca todas as instancias
const io = new Server(app.listen(3000));
io.adapter(createAdapter(pub, sub));
io.on('connection', (s) => s.on('msg', (m) => io.emit('msg', m)));
