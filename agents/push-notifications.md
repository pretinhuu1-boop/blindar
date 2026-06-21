---
name: push-notifications
category: frontend
module: 10
priority: P1
description: |
  Web Push (VAPID) + FCM (Android) + APNs (iOS): consent gradual (NUNCA
  pedir no load), quiet hours (não acordar user 2h da manhã), fallback
  chain (push → email → in-app), tracking de delivery, dedup, payload
  curto, deep links que abrem na rota certa, opt-out granular por tipo.
---

# Agent: push-notifications

## Missão

Push errado vira motivo de desinstalar app. Pedir permissão no load = 80%
nega para sempre. Mandar de madrugada = uninstall. Este agente prescreve
push que **engaja sem irritar**.

## Quando rodar

- Módulo 10 selecionado E projeto tem usuário identificado
- Detectado: `web-push`, `firebase-admin`, `node-apn`, manifest com SW
- Operador pediu "notificação", "push", "engajamento"

## A. Stack por target

| Target | Lib | Custo |
|---|---|---|
| Web (Chrome/Edge/Firefox) | `web-push` (VAPID) | Free, self-host |
| Web (Safari macOS) | Web Push (Safari 16.4+) | Free |
| Web (Safari iOS) | Web Push (precisa estar instalado como PWA) | Free |
| Android nativo | FCM (Firebase Cloud Messaging) | Free até milhões/mês |
| iOS nativo | APNs (Apple Push) | Free, exige cert |
| Multi-platform managed | OneSignal, Pusher Beams, Knock | Pago |

## B. Consent gradual (NUNCA no load)

```ts
// RUIM
useEffect(() => { Notification.requestPermission(); }, []);  // 80% nega

// BOM — pedir DEPOIS de user interagir e ver valor
function NotificationCTA() {
  const [perm, setPerm] = useState(Notification.permission);
  if (perm === 'granted') return null;
  if (perm === 'denied') return <DeniedFallback />;  // sugere email
  return (
    <Card>
      <h3>Receba lembretes 2h antes do seu horário</h3>
      <p>Pra não esquecer compromissos. Você pode desligar quando quiser.</p>
      <Button onClick={async () => {
        const r = await Notification.requestPermission();
        setPerm(r);
        if (r === 'granted') await subscribe();
      }}>Ativar notificações</Button>
      <Button variant="ghost" onClick={dismiss}>Agora não</Button>
    </Card>
  );
}
```

## C. Subscribe + salvar no backend

```ts
async function subscribe() {
  const reg = await navigator.serviceWorker.ready;
  const sub = await reg.pushManager.subscribe({
    userVisibleOnly: true,  // OBRIGATÓRIO (não fazer push silencioso)
    applicationServerKey: VAPID_PUBLIC_KEY,
  });
  await fetch('/api/push/subscribe', { method: 'POST', body: JSON.stringify(sub) });
}
```

Backend salva por user — múltiplos devices.

## D. Preferências por tipo (opt-in granular)

```sql
CREATE TABLE notification_preferences (
  user_id      UUID PRIMARY KEY,
  appointment_reminder BOOLEAN DEFAULT true,
  appointment_change   BOOLEAN DEFAULT true,
  marketing            BOOLEAN DEFAULT false,
  quiet_hours_start    TIME DEFAULT '22:00',
  quiet_hours_end      TIME DEFAULT '08:00',
  timezone             TEXT NOT NULL DEFAULT 'America/Sao_Paulo'
);
```

Antes de cada envio: respeita prefs + quiet hours convertidas pra timezone do user.

## E. Payload (< 4KB)

```json
{
  "title": "João confirmou às 14h",
  "body": "Cabelo de cor — 2 horas",
  "icon": "/icons/icon-192.png",
  "badge": "/icons/badge-72.png",
  "tag": "apt-abc",
  "renotify": false,
  "data": { "url": "/appointments/abc" },
  "actions": [
    { "action": "view", "title": "Ver" },
    { "action": "snooze", "title": "Adiar 15min" }
  ]
}
```

- Title ≤ 50 chars
- Body ≤ 100 chars
- `tag` pra dedup (mesma tag substitui notificação anterior)
- Sempre `data.url` pra deep link

## F. Service Worker handler

```js
// public/sw.js
self.addEventListener('push', (event) => {
  const data = event.data.json();
  event.waitUntil(
    self.registration.showNotification(data.title, {
      body: data.body, icon: data.icon, badge: data.badge,
      tag: data.tag, renotify: data.renotify,
      data: data.data, actions: data.actions,
    })
  );
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const action = event.action;
  const url = action === 'snooze' ? '/api/notif/snooze' : event.notification.data.url;
  event.waitUntil(clients.openWindow(url));
});
```

## G. Backend envio

```ts
import webpush from 'web-push';

webpush.setVapidDetails('mailto:admin@example.com', VAPID_PUBLIC, VAPID_PRIVATE);

async function sendPush(userId: string, payload: NotificationPayload) {
  // 1. Check prefs + quiet hours
  const prefs = await db.notificationPreferences.findUnique({ where: { userId } });
  if (!prefs[payload.type]) return { skipped: 'opt_out' };
  if (inQuietHours(prefs)) return await scheduleForLater(userId, payload);

  // 2. Pega subscriptions desse user
  const subs = await db.pushSubscription.findMany({ where: { userId, active: true } });

  // 3. Envia em paralelo + tracking
  const results = await Promise.allSettled(subs.map(sub =>
    webpush.sendNotification(sub.endpoint, JSON.stringify(payload), { TTL: 60 * 60 * 24 })
  ));

  // 4. Marca inativos os que retornaram 410/404
  for (let i = 0; i < results.length; i++) {
    const r = results[i];
    if (r.status === 'rejected' && [404, 410].includes(r.reason?.statusCode)) {
      await db.pushSubscription.update({ where: { id: subs[i].id }, data: { active: false } });
    }
  }

  return { sent: results.filter(r => r.status === 'fulfilled').length };
}
```

## H. Quiet hours (não acordar user)

```ts
function inQuietHours(prefs: NotificationPreferences): boolean {
  const now = DateTime.now().setZone(prefs.timezone);
  const [sh, sm] = prefs.quiet_hours_start.split(':').map(Number);
  const [eh, em] = prefs.quiet_hours_end.split(':').map(Number);
  const cur = now.hour * 60 + now.minute;
  const start = sh * 60 + sm, end = eh * 60 + em;
  return start < end ? cur >= start && cur < end : cur >= start || cur < end;
}
```

Tipos "críticos" (auth alert, payment failure) ignoram quiet hours.

## I. Fallback chain (push → email → in-app)

```ts
async function notify(userId: string, payload: Payload) {
  const result = await sendPush(userId, payload);
  if (result.sent > 0) return;            // chegou
  await email.send(userId, payload);       // tenta email
  await inApp.create(userId, payload);     // sempre cria badge in-app
}
```

## J. Métricas

- Delivery rate > 95% (de quem deu permissão)
- Click-through rate > 5%
- Opt-out rate < 2%
- Tempo de subscribe (consent given → endpoint saved) < 2s

## K. Greps

```bash
# Permission no load (CRIT)
rg -n "Notification\.requestPermission" --type ts -B 5 | rg "useEffect\(\(\) =>"

# Push sem userVisibleOnly (Chrome bane app)
rg -n "pushManager\.subscribe" --type ts -A 3 | rg -v "userVisibleOnly: true"

# Payload sem TTL (perdido se device offline)
rg -n "webpush\.sendNotification" --type ts | rg -v "TTL"

# Sem dedup tag
rg -n "showNotification" --type js -A 10 | rg -v "tag:"
```

## Output em sec.html

```
┌─ Push Notifications (Módulo 10) ─────────────────────────┐
│ VAPID configurado            : ✅                          │
│ Service Worker handler       : ✅                          │
│ Consent gradual (não no load): ✅                          │
│ Subscribe com userVisibleOnly: ✅                          │
│ Preferências por tipo        : ✅ tabela                  │
│ Quiet hours                  : ✅ 22-08 default          │
│ Fallback chain (email/in-app): ✅                          │
│ Cleanup de subs inválidos    : ✅ 410/404                 │
│ Deep links                   : ✅                          │
│ Payload < 4KB                : ✅                          │
│ Tag dedup                    : ✅                          │
│ Delivery rate (30d)          : 97.2% ✅                    │
│ Opt-out rate                 : 1.1% ✅                     │
│ Status                       : ✅ ENGAGING                │
└───────────────────────────────────────────────────────────┘
```

## Anti-padrões

- ❌ `requestPermission()` no load (queima permissão pra sempre)
- ❌ Sem `userVisibleOnly: true` (Chrome bane silent push)
- ❌ Mandar push 2h da manhã sem quiet hours
- ❌ Sem opt-out granular (só "ativar tudo / desativar tudo")
- ❌ Payload > 4KB (Chrome rejeita)
- ❌ Sem `tag` pra dedup (5 notif iguais empilhadas)
- ❌ Sem cleanup de subscriptions inválidas (envio falha em loop)
- ❌ Sem fallback (push falhou = user nunca soube)
- ❌ Marketing sem opt-in EXPLÍCITO (LGPD violation)
- ❌ Deep link genérico ("/") em vez da rota específica
- ❌ Sem TTL (notif chega 2 dias depois fora de contexto)
