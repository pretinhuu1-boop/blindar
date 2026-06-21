---
name: auth-premium
category: security
module: 2
priority: P0
description: |
  Stack de autenticação premium: WebAuthn (FaceID/TouchID/Windows Hello),
  refresh token com rotação + reuse detection, idle timeout configurável
  (default 15min) com PIN/senha de retomada SEM perder estado da página,
  Argon2id pra senhas, JWT RS256/EdDSA. Substitui auth caseira por padrão
  comprovado.
---

# Agent: auth-premium

## Missão

Eliminar 3 dores comuns de auth em produção:

1. **Login chato e inseguro** → WebAuthn (biometria sem senha, padrão W3C)
2. **Sessão que expira no meio do trabalho** → idle timeout com PIN de
   retomada, estado preservado
3. **Token roubado vira conta tomada** → refresh rotation + reuse detection

## Quando rodar

- Módulo 2 selecionado E projeto tem auth de usuário (não CLI/lib sem login)
- Detectado: `package.json` com `next-auth`/`@auth/core`/`passport`/`lucia`/
  `better-auth`/`jsonwebtoken`/`jose`/qualquer libauth
- Operador pediu "biometria" / "passkey" / "FaceID" / "refresh token" /
  "PIN" / "sessão segura"

## A. Senhas (baseline obrigatório)

### Hash: Argon2id (NÃO bcrypt em projeto novo)

```ts
import argon2 from 'argon2';

const hash = await argon2.hash(password, {
  type: argon2.argon2id,
  memoryCost: 19 * 1024,  // 19 MiB (OWASP 2024)
  timeCost: 2,             // 2 iterations
  parallelism: 1,
  hashLength: 32
});
```

**Greps:**
```bash
# Detecta bcrypt em projeto que poderia migrar
rg -n "bcrypt|bcryptjs" package.json src/

# Detecta MD5/SHA1 em senhas (CRIT — bloqueia release)
rg -ni "(md5|sha1).*password" --type ts --type js --type py
```

### Política de senha (mínimo)

- 12+ caracteres (não 8 — 2025 baseline NIST)
- Validar contra **HaveIBeenPwned** (k-anonymity, sem expor a senha)
- Permitir spaces, emojis, unicode
- NÃO forçar expiração periódica (NIST removeu essa regra em 2020)
- NÃO forçar caractere especial (NIST: composição não aumenta força real)

```ts
import { sha1 } from '@noble/hashes/sha1';

async function isPwned(password: string): Promise<boolean> {
  const hash = Array.from(sha1(password)).map(b => b.toString(16).padStart(2,'0')).join('').toUpperCase();
  const prefix = hash.slice(0, 5);
  const suffix = hash.slice(5);
  const res = await fetch(`https://api.pwnedpasswords.com/range/${prefix}`);
  const text = await res.text();
  return text.split('\n').some(line => line.startsWith(suffix));
}
```

## B. WebAuthn / Passkeys (biometria sem senha)

Padrão W3C suportado em: iOS Safari 16+ (FaceID/TouchID), Android Chrome
9+ (fingerprint/face unlock), Windows Hello, macOS Safari 16+ (TouchID),
YubiKey/SoloKey/chaves físicas.

### Libs recomendadas

```bash
npm i @simplewebauthn/server @simplewebauthn/browser
```

### Fluxo: registro de credencial

```ts
// Backend (Node)
import { generateRegistrationOptions, verifyRegistrationResponse } from '@simplewebauthn/server';

// 1. Pedir options
app.post('/auth/webauthn/register/options', async (req, res) => {
  const user = req.user;  // user já logado com senha
  const options = await generateRegistrationOptions({
    rpName: 'Salon Pro',
    rpID: 'salonpro.com',           // domínio sem protocolo
    userID: user.id,
    userName: user.email,
    attestationType: 'none',          // simple, sem audit chain
    excludeCredentials: user.passkeys.map(p => ({ id: p.credentialId, type: 'public-key' })),
    authenticatorSelection: {
      residentKey: 'preferred',
      userVerification: 'required',   // biometria obrigatória
      authenticatorAttachment: 'platform'  // FaceID/TouchID (não chave física)
    },
  });
  req.session.challenge = options.challenge;
  res.json(options);
});

// 2. Verificar e salvar
app.post('/auth/webauthn/register/verify', async (req, res) => {
  const verification = await verifyRegistrationResponse({
    response: req.body,
    expectedChallenge: req.session.challenge,
    expectedOrigin: 'https://salonpro.com',
    expectedRPID: 'salonpro.com',
  });
  if (verification.verified) {
    await db.passkey.create({
      data: {
        userId: req.user.id,
        credentialId: verification.registrationInfo!.credentialID,
        publicKey: verification.registrationInfo!.credentialPublicKey,
        counter: verification.registrationInfo!.counter,
        deviceName: req.body.deviceName ?? 'Dispositivo',
      }
    });
  }
  res.json({ verified: verification.verified });
});
```

```ts
// Frontend
import { startRegistration } from '@simplewebauthn/browser';

async function enableBiometric() {
  const optsRes = await fetch('/auth/webauthn/register/options', { method: 'POST' });
  const opts = await optsRes.json();
  const att = await startRegistration(opts);
  await fetch('/auth/webauthn/register/verify', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(att)
  });
}
```

### Fluxo: login com biometria

Espelha o registro com `generateAuthenticationOptions` /
`verifyAuthenticationResponse`. Após verify OK, emite o mesmo par
access+refresh token de um login normal.

### UX

- Tela de login: campo email + botão "Entrar com biometria" (se credencial existe)
- Em Settings/Perfil: "Ativar FaceID" / "Ativar TouchID" / "Adicionar passkey"
- Lista de passkeys cadastradas com `deviceName` e botão remover
- Sempre permitir fallback senha (1 dispositivo perdido não trava o user)

## C. JWT + Refresh com rotação + reuse detection

### Access token

- **JWT RS256 ou EdDSA** (não HS256 — chave compartilhada em microsserviços = risco)
- Duração: **15 minutos** (default)
- Payload mínimo: `sub`, `aud`, `iss`, `iat`, `exp`, `role`, `tenantId`
- Armazenamento client: **memória** (variável JS) OU `sessionStorage`
- **NUNCA** `localStorage` (XSS lê)

### Refresh token

- Opaque random (não JWT — não precisa decode no client)
- 256 bits aleatórios via `crypto.randomBytes(32)`, base64url
- Armazenamento client: **httpOnly cookie** (Secure, SameSite=Strict, Path=/)
- Persistido no DB com hash (Argon2id) + `userId` + `family_id` (UUID)
- Duração: 7 dias absoluto + 24h sliding (renova se usado)

### Rotação obrigatória

Cada uso do refresh:
1. Valida hash no DB
2. Marca refresh anterior como `used_at = now`
3. Emite NOVO refresh com mesmo `family_id`
4. Retorna par novo (access + refresh) ao client

### Reuse detection (sinal de roubo)

Se um refresh **já usado** é apresentado de novo → **alguém roubou**.
Ação:
1. Invalidar TODOS refresh com mesmo `family_id` (logout total daquele user)
2. Logar evento de segurança (audit)
3. Notificar user por email/push: "Atividade suspeita detectada"

```ts
async function refreshTokens(refreshToken: string) {
  const hash = await argon2.hash(refreshToken, { type: argon2.argon2id });
  const stored = await db.refreshToken.findUnique({ where: { hash } });
  if (!stored) throw new Unauthorized('refresh invalid');

  if (stored.used_at) {
    // REUSE DETECTED — token roubado
    await db.refreshToken.updateMany({
      where: { family_id: stored.family_id },
      data: { revoked_at: new Date(), revoke_reason: 'reuse_detected' }
    });
    await audit.log('refresh_reuse_detected', { userId: stored.userId, family: stored.family_id });
    await notifyUser(stored.userId, 'security_alert');
    throw new Unauthorized('session compromised, please login again');
  }

  if (stored.revoked_at || stored.expires_at < new Date()) {
    throw new Unauthorized('refresh expired');
  }

  // OK — rotaciona
  await db.refreshToken.update({ where: { id: stored.id }, data: { used_at: new Date() } });
  const newAccess = signJWT({ sub: stored.userId, /* ... */ }, { expiresIn: '15m' });
  const newRefresh = await issueRefresh({ userId: stored.userId, family_id: stored.family_id });
  return { accessToken: newAccess, refreshToken: newRefresh };
}
```

### Auto-refresh no client

```ts
// Refresh 60s ANTES de expirar
let accessToken = null;
let refreshTimer = null;

function scheduleRefresh(expiresInSec: number) {
  clearTimeout(refreshTimer);
  refreshTimer = setTimeout(async () => {
    const { accessToken: newAT } = await fetch('/auth/refresh', { method: 'POST', credentials: 'include' }).then(r => r.json());
    accessToken = newAT;
    scheduleRefresh(15 * 60);
  }, (expiresInSec - 60) * 1000);
}
```

## D. Idle timeout 15min + PIN de retomada (sem perder estado)

### Detector de inatividade

```ts
// hooks/useIdleTimer.ts
const IDLE_MS = 15 * 60 * 1000;
let lastActivity = Date.now();
let lockTimer: ReturnType<typeof setTimeout>;

function reset() {
  lastActivity = Date.now();
  clearTimeout(lockTimer);
  lockTimer = setTimeout(lock, IDLE_MS);
}

function lock() {
  // 1. Salva estado da página
  saveDraft();                              // forms, query, scroll, modais abertos
  // 2. Mostra overlay PIN (não derruba sessão)
  showLockOverlay();
  // 3. Access token continua válido até expirar normalmente
}

['mousedown','keydown','scroll','touchstart'].forEach(e =>
  window.addEventListener(e, reset, { passive: true })
);

// Sincroniza entre tabs (BroadcastChannel)
const channel = new BroadcastChannel('activity');
channel.onmessage = (e) => { if (e.data === 'activity') reset(); };
window.addEventListener('mousedown', () => channel.postMessage('activity'));
```

### PIN de retomada

User cadastra PIN 4-6 dígitos (separado da senha) em Settings.

```ts
// Backend
const pinHash = await argon2.hash(pin, { type: argon2.argon2id });
await db.user.update({ where: { id }, data: { pinHash, pinAttempts: 0 } });

// Validate
async function validatePin(userId: string, pin: string) {
  const user = await db.user.findUnique({ where: { id: userId } });
  if (user.pinAttempts >= 5) {
    // 5 tentativas erradas → cai pra senha completa
    return { ok: false, mustUsePassword: true };
  }
  const ok = await argon2.verify(user.pinHash, pin);
  if (!ok) {
    await db.user.update({ where: { id: userId }, data: { pinAttempts: { increment: 1 } } });
    return { ok: false };
  }
  await db.user.update({ where: { id: userId }, data: { pinAttempts: 0 } });
  return { ok: true };
}
```

### Preservação de estado (não perder trabalho)

```ts
// pages/PageX.tsx — auto-save draft a cada mudança
const [form, setForm] = useState(loadDraft('form-x') ?? defaultForm);
useEffect(() => {
  const t = setTimeout(() => saveDraft('form-x', form), 500);
  return () => clearTimeout(t);
}, [form]);

// On unlock: tudo continua na tela.
// Scroll position: salva window.scrollY no lock, restaura no unlock.
// Modais abertos: armazena flag.
// Tab ativa: roteador preserva URL.
```

**Regra:** PIN errado **não derruba sessão imediatamente** — só após 5
tentativas. Se errou 5x → exige senha completa. Se senha 3x → logout.

### Biometria como alternativa ao PIN

Se user tem passkey cadastrada → mostra "Desbloquear com biometria" antes
do PIN. WebAuthn `userVerification: 'required'` valida sem digitar nada.

## E. CORS, CSRF, headers (super seguro)

```ts
// CORS — allowlist explícita
app.use(cors({
  origin: ['https://salonpro.com', 'https://app.salonpro.com'],
  credentials: true,
  methods: ['GET','POST','PUT','PATCH','DELETE'],
  allowedHeaders: ['Content-Type','Authorization'],
  maxAge: 600
}));

// NÃO usar origin: '*'
// NÃO usar origin: true (reflete qualquer)

// CSRF — double-submit + SameSite=Strict cobre 99%
// Pra forms tradicionais, usar token CSRF (csurf ou similar)

// Headers de segurança (Helmet ou manual)
app.use((req, res, next) => {
  res.setHeader('Strict-Transport-Security', 'max-age=31536000; includeSubDomains; preload');
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('X-Frame-Options', 'DENY');
  res.setHeader('Referrer-Policy', 'strict-origin-when-cross-origin');
  res.setHeader('Permissions-Policy', 'camera=(), microphone=(), geolocation=()');
  res.setHeader('Content-Security-Policy', "default-src 'self'; script-src 'self' 'wasm-unsafe-eval'; img-src 'self' data: https:; style-src 'self' 'unsafe-inline'; connect-src 'self' https://api.salonpro.com; frame-ancestors 'none'");
  next();
});
```

## F. Rate limit (anti-brute force)

| Endpoint | Limite |
|---|---|
| `POST /auth/login` | 5/15min/IP + 5/15min/email |
| `POST /auth/refresh` | 10/min/refreshToken |
| `POST /auth/forgot-password` | 3/hora/email |
| `POST /auth/webauthn/*` | 10/min/IP |
| `POST /auth/pin/verify` | 5/min/userId |

Bib: `@upstash/ratelimit`, `express-rate-limit`, `@fastify/rate-limit`.

## Output esperado em sec.html

```
┌─ Auth Premium (Módulo 2) ────────────────────────────────┐
│ Hash de senha                : Argon2id ✅ (era bcrypt)   │
│ JWT algoritmo                : RS256 ✅                    │
│ Access token expira em       : 15min ✅                    │
│ Refresh token rotation       : ✅ ativo                    │
│ Refresh reuse detection      : ✅ ativo (testado)          │
│ WebAuthn/Passkeys            : ✅ implementado             │
│ Idle timeout                 : 15min ✅ configurável       │
│ PIN de retomada              : ✅ 4-6 dígitos, 5 tentativas│
│ Estado preservado em lock    : ✅ form drafts + scroll     │
│ Pwned password check         : ✅ HIBP k-anonymity         │
│ CORS allowlist explícita     : ✅                          │
│ Rate limit login             : ✅ 5/15min                  │
│ Headers segurança (8)        : ✅ todos presentes          │
│ Status                       : ✅ PRODUCTION-READY        │
└───────────────────────────────────────────────────────────┘
```

## Anti-padrões (CRIT — bloqueia release)

- ❌ JWT no localStorage (XSS lê)
- ❌ Refresh token sem rotação
- ❌ HS256 com chave compartilhada em microsserviços
- ❌ bcrypt em projeto **novo** (use Argon2id; bcrypt é OK em legacy)
- ❌ MD5/SHA1 pra senha
- ❌ CORS `origin: '*'` com `credentials: true` (browser bloqueia, mas configurou errado)
- ❌ Refresh token retornado no body JSON (deve vir em httpOnly cookie)
- ❌ Idle timeout que **desloga** sem chance de retomar (perde trabalho)
- ❌ PIN compartilhar hash com senha (PIN pode ser fraco — hash separado)
- ❌ WebAuthn sem `userVerification: 'required'` (vira "qualquer pessoa com o device")
- ❌ Sem rate limit em /auth/* (brute force fácil)
