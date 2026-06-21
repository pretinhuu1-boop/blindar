---
name: realtime
category: api
module: 4
priority: P1
description: |
  WebSockets/SSE/CRDT corretos: auth no handshake, heartbeat + reconnect
  backoff, rooms por tenant (sem broadcast cross-tenant), presença,
  rate limit por conexão, scaling com Redis adapter, fallback gracioso,
  cleanup de zombies. Para apps com chat, notificações in-app, dashboard
  live, colaboração simultânea.
---

# Agent: realtime

## Missão

Real-time errado vira leak (broadcast cross-tenant), DoS (sem limit) ou
fantasma (conexão zumbi consome RAM). Este agente prescreve a stack
correta de WS/SSE/CRDT pra apps em produção.

## Quando rodar

- Módulo 4 selecionado
- Detectado: `socket.io`, `ws`, `@nestjs/websockets`, `EventSource`, `yjs`, `liveblocks`, `pusher`, `ably`
- Operador pediu "chat", "notificação ao vivo", "dashboard live", "colaboração"

## A. Escolha de protocolo

| Necessidade | Protocolo |
|---|---|
| Server → client unidirecional (notif, dashboard) | **SSE** (Server-Sent Events) — HTTP/2 OK, simples |
| Bidirecional (chat, presença) | **WebSocket** com Socket.IO (fallback) ou `ws` puro |
| Colaboração concorrente (Docs/Figma-like) | **CRDT** (Yjs + y-websocket) ou **Liveblocks** |
| Push do servidor com retry | **Server-Sent Events** > WS pra esse caso |

NÃO usar long-polling em projeto novo. NÃO subir WS sem proxy WS-aware
(CloudFlare WS, nginx upgrade, ALB WebSocket support).

## B. Auth no handshake (não confiar no client)

```ts
io.use(async (socket, next) => {
  // Token via auth.token (Socket.IO) ou query (NÃO via URL path)
  const token = socket.handshake.auth?.token || socket.handshake.headers.cookie?.match(/access_token=([^;]+)/)?.[1];
  if (!token) return next(new Error('unauthorized'));
  try {
    const user = await verifyJWT(token);
    if (user.exp < Date.now() / 1000) return next(new Error('expired'));
    socket.data.user = user;
    socket.data.tenantId = user.tenantId;
    next();
  } catch { next(new Error('invalid_token')); }
});
```

## C. Rooms por tenant (zero broadcast cross-tenant)

```ts
io.on('connection', (socket) => {
  const { user, tenantId } = socket.data;
  // SEMPRE prefixar com tenant
  socket.join(`tenant:${tenantId}`);
  if (user.role === 'OPERACIONAL') socket.join(`user:${user.id}`);

  socket.on('subscribe:appointment', (id) => {
    // Valida que appointment pertence ao tenant ANTES de juntar
    if (await canAccess(user, 'appointment', id)) socket.join(`appointment:${id}`);
  });
});

// Broadcast: SEMPRE namespaced
io.to(`tenant:${tenantId}`).emit('apt.created', payload);
```

## D. Heartbeat + reconnect

```ts
// Server: ping a cada 25s, timeout 5s, conexão morre se sem pong
const io = new Server(server, { pingInterval: 25_000, pingTimeout: 5_000 });

// Client: reconnect exponencial
const socket = io({ reconnection: true, reconnectionDelay: 1_000, reconnectionDelayMax: 30_000, randomizationFactor: 0.5 });
socket.on('disconnect', (reason) => { if (reason === 'io server disconnect') socket.connect(); });
```

## E. Scaling horizontal (múltiplos servidores)

```ts
// Redis adapter (Socket.IO) ou Cluster mode
import { createAdapter } from '@socket.io/redis-adapter';
io.adapter(createAdapter(pubClient, subClient));

// OU sticky session no LB (cada conexão fixa em 1 instância)
```

Sem isso, emit em 1 server não chega em clients conectados em outro.

## F. Rate limit por conexão

```ts
// Tokens por segundo, anti-spam
const buckets = new Map<string, { count: number; reset: number }>();
socket.use(([event, ...args], next) => {
  const k = socket.data.user.id;
  const now = Date.now();
  const b = buckets.get(k) ?? { count: 0, reset: now + 1000 };
  if (now > b.reset) { b.count = 0; b.reset = now + 1000; }
  if (++b.count > 20) return next(new Error('rate_limited'));
  buckets.set(k, b);
  next();
});

// Limite de payload (anti-DoS de memory)
io.engine.opts.maxHttpBufferSize = 64 * 1024;  // 64KB
```

## G. Presença (quem está online)

```ts
const onlineUsers = new Map<string, Set<string>>();  // tenantId → set of userIds

socket.on('connection', () => {
  const set = onlineUsers.get(tenantId) ?? new Set();
  set.add(user.id);
  onlineUsers.set(tenantId, set);
  io.to(`tenant:${tenantId}`).emit('presence:online', [...set]);
});
socket.on('disconnect', () => {
  onlineUsers.get(tenantId)?.delete(user.id);
  io.to(`tenant:${tenantId}`).emit('presence:online', [...(onlineUsers.get(tenantId) ?? [])]);
});
```

Em scaling com Redis: presença vai pra Redis SET com TTL, não memória local.

## H. CRDT (Yjs) pra colaboração

```ts
// Server: y-websocket relay (não persiste; doc fica em DB separado)
import { setupWSConnection } from 'y-websocket/bin/utils';
const wss = new WebSocketServer({ server });
wss.on('connection', (ws, req) => {
  // Auth idêntica ao Socket.IO acima
  setupWSConnection(ws, req, { docName: extractDocId(req), gc: true });
});

// Persistir doc periodicamente em DB
setInterval(() => persistAllDocs(), 30_000);
```

## I. Greps obrigatórios

```bash
# WS sem auth (CRIT — qualquer um conecta)
rg -n "io\.on\(['\"]connection" --type ts -A 10 | rg -v "auth|verify|jwt"

# Broadcast sem tenant prefix
rg -n "io\.emit\(" --type ts | rg -v "tenant:|user:"

# Sem rate limit em socket
rg -n "socket\.on\(['\"](?!disconnect|error)" --type ts | head

# Token em URL path (vaza em logs)
rg -n "io\(['\"]ws://.*token=" --type ts
```

## Output em sec.html

```
┌─ Realtime (Módulo 4) ────────────────────────────────────┐
│ Protocolo                     : Socket.IO + Redis adapter│
│ Auth no handshake             : ✅ JWT verify             │
│ Rooms por tenant              : ✅ namespaced             │
│ Heartbeat (25s/5s)            : ✅                         │
│ Reconnect com backoff         : ✅                         │
│ Rate limit por conexão        : ✅ 20 msg/s               │
│ Max payload                   : 64 KB                      │
│ Scaling horizontal            : ✅ Redis adapter           │
│ Presença com TTL              : ✅                         │
│ Conexões zumbi cleanup        : ✅ heartbeat              │
│ Cross-tenant broadcast        : 0 ✅ (testes provam)      │
│ Status                        : ✅ READY                  │
└───────────────────────────────────────────────────────────┘
```

## Anti-padrões

- ❌ WS sem auth no handshake
- ❌ Broadcast `io.emit(...)` sem namespace (vaza cross-tenant)
- ❌ Sem rate limit (1 cliente derruba server)
- ❌ Sem maxHttpBufferSize (atacante manda payload gigante)
- ❌ Token em URL (vaza em logs/proxies)
- ❌ Long polling em projeto novo (use SSE)
- ❌ Subir WS atrás de proxy sem WS upgrade configurado
- ❌ Sem heartbeat (zumbis consomem RAM)
- ❌ Single-server sem Redis adapter (não escala horizontal)
- ❌ Sem persistência de CRDT (refresh = perde edição)
- ❌ Presença em memória local (em scale-out, vê só parte dos users)
