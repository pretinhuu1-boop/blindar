---
name: pwa-installable
category: frontend
module: 10
priority: P2
description: |
  Torna o projeto instalável como app no celular (iOS/Android) e no
  desktop (Windows/macOS/Linux) via PWA (Progressive Web App).
  Cobre manifest, service worker, ícones, install prompt, offline básico
  e push notifications opcionais.
---

# Agent: pwa-installable

## Missão

Qualquer projeto com UI deve ser **instalável** como app nativo no celular
e notebook — sem app store, sem SDK proprietário. Funciona em iOS 16.4+,
Android Chrome, Windows Edge/Chrome, macOS Safari 17+.

## Quando rodar

- Módulo 10 selecionado E `ui_detected: true`
- Operador pediu "instalável" / "PWA" / "app no celular"
- Projeto tipo `saas` / `ecom` / `landing` / `mobile`

## Checklist obrigatório

### 1. `public/manifest.webmanifest`

```json
{
  "name": "Salon Pro",
  "short_name": "SalonPro",
  "description": "Sistema de gestão para salões",
  "id": "/",
  "start_url": "/?source=pwa",
  "scope": "/",
  "display": "standalone",
  "display_override": ["window-controls-overlay", "standalone"],
  "orientation": "portrait",
  "background_color": "#ffffff",
  "theme_color": "#0066cc",
  "icons": [
    { "src": "/icons/icon-192.png", "sizes": "192x192", "type": "image/png", "purpose": "any" },
    { "src": "/icons/icon-512.png", "sizes": "512x512", "type": "image/png", "purpose": "any" },
    { "src": "/icons/icon-maskable-192.png", "sizes": "192x192", "type": "image/png", "purpose": "maskable" },
    { "src": "/icons/icon-maskable-512.png", "sizes": "512x512", "type": "image/png", "purpose": "maskable" }
  ],
  "screenshots": [
    { "src": "/screenshots/mobile-1.png", "sizes": "750x1334", "type": "image/png", "form_factor": "narrow" },
    { "src": "/screenshots/desktop-1.png", "sizes": "1280x720", "type": "image/png", "form_factor": "wide" }
  ],
  "shortcuts": [
    { "name": "Agenda do dia", "url": "/agenda/hoje" }
  ],
  "categories": ["business", "productivity"]
}
```

**Validações:**
- [ ] `name` e `short_name` definidos
- [ ] `display: standalone` (não `browser`)
- [ ] Ícones 192x192 **E** 512x512 (mínimo)
- [ ] 1 ícone `purpose: maskable` (Android adaptive icons)
- [ ] `start_url` aponta pra rota inicial (não login se possível)
- [ ] `theme_color` e `background_color` definidos

### 2. Service Worker (`public/sw.js` ou via lib)

**Lib recomendada**: Workbox (`workbox-window`) ou Vite PWA Plugin
(`vite-plugin-pwa`). NÃO escrever SW na mão a menos que projeto tiny.

```js
// vite.config.ts (exemplo)
import { VitePWA } from 'vite-plugin-pwa';

export default {
  plugins: [
    VitePWA({
      registerType: 'autoUpdate',
      manifest: { /* refs ao manifest.webmanifest */ },
      workbox: {
        runtimeCaching: [
          { urlPattern: /\.(?:png|jpg|jpeg|svg|webp)$/, handler: 'CacheFirst', options: { cacheName: 'images', expiration: { maxAgeSeconds: 60 * 60 * 24 * 30 } } },
          { urlPattern: /^https:\/\/fonts\./, handler: 'StaleWhileRevalidate', options: { cacheName: 'fonts' } },
          { urlPattern: /\/api\/.*/, handler: 'NetworkFirst', options: { cacheName: 'api', networkTimeoutSeconds: 3 } }
        ]
      }
    })
  ]
}
```

**Validações:**
- [ ] SW registrado em produção (não em dev)
- [ ] Atualização automática com prompt (não force reload)
- [ ] Cache de assets estáticos (immutable, hash no filename)
- [ ] Cache de API com fallback (NetworkFirst, timeout 3s)
- [ ] Página offline (`/offline.html`) pra rotas não cacheadas
- [ ] `skipWaiting()` só com confirmação do usuário (evita perder form em digitação)

### 3. Link no `<head>` (Next.js: `app/layout.tsx`)

```html
<link rel="manifest" href="/manifest.webmanifest" />
<meta name="theme-color" content="#0066cc" />
<meta name="apple-mobile-web-app-capable" content="yes" />
<meta name="apple-mobile-web-app-status-bar-style" content="default" />
<meta name="apple-mobile-web-app-title" content="SalonPro" />
<link rel="apple-touch-icon" href="/icons/apple-icon-180.png" />
<link rel="icon" type="image/png" sizes="32x32" href="/icons/icon-32.png" />
<link rel="icon" type="image/png" sizes="16x16" href="/icons/icon-16.png" />
```

### 4. Install prompt customizado (UX)

NÃO depender do prompt nativo do browser (raramente aparece). Implementar
banner discreto + botão "Instalar app" no menu de configurações.

```ts
// hooks/useInstallPrompt.ts
const [deferredPrompt, setDeferredPrompt] = useState<any>(null);
const [canInstall, setCanInstall] = useState(false);

useEffect(() => {
  const handler = (e: any) => {
    e.preventDefault();
    setDeferredPrompt(e);
    setCanInstall(true);
  };
  window.addEventListener('beforeinstallprompt', handler);
  return () => window.removeEventListener('beforeinstallprompt', handler);
}, []);

async function install() {
  if (!deferredPrompt) return;
  deferredPrompt.prompt();
  const { outcome } = await deferredPrompt.userChoice;
  if (outcome === 'accepted') setCanInstall(false);
  setDeferredPrompt(null);
}
```

**iOS Safari não suporta `beforeinstallprompt`** — exibir tutorial:
"Toque em Compartilhar → Adicionar à Tela de Início".

### 5. Detecção de modo standalone

```ts
const isStandalone = window.matchMedia('(display-mode: standalone)').matches
                  || (window.navigator as any).standalone === true;  // iOS
```

Esconder banner "instalar" quando já está instalado. Mostrar features
exclusivas (push, share, file handling) quando standalone.

### 6. Ícones — geração automatizada

Usar `pwa-asset-generator` ou `@vite-pwa/assets-generator`:

```bash
npx pwa-asset-generator logo.svg ./public/icons \
  --background "#ffffff" --padding "12%" --opaque false
```

Gera: 192, 512, maskable, apple-touch (180), favicon, splash screens iOS.

## Push notifications (opcional, módulo extra)

Se projeto usa, implementar com **Web Push API + VAPID**:
- Permission API (pedir só após interação do user)
- `Notification.requestPermission()` com fallback gracioso
- Backend envia via Web Push Protocol (lib: `web-push` no Node)
- Service Worker `addEventListener('push', ...)`
- **NUNCA** pedir permissão no load — só após user clicar "Ativar notificações"

## Lighthouse PWA audit

Bloqueia merge se Lighthouse PWA score < 90. Critérios:
- [ ] Manifest tem nome, ícone, theme_color, background_color, display
- [ ] Service worker registrado
- [ ] HTTPS (requisito pra SW em prod)
- [ ] Viewport meta tag
- [ ] Apple touch icon
- [ ] Splash screen iOS (apple-touch-startup-image)
- [ ] `theme-color` <meta> e no manifest

## Output esperado em sec.html

```
┌─ PWA Installable (Módulo 10) ────────────────────────────┐
│ manifest.webmanifest         : ✅ válido (W3C check)      │
│ Service Worker registrado    : ✅ em produção             │
│ Ícones (192/512/maskable)    : ✅ 4 tamanhos              │
│ iOS apple-touch-icon         : ✅                          │
│ Lighthouse PWA score         : 94 ✅                       │
│ Install prompt customizado   : ✅                          │
│ Offline page                 : ✅ /offline.html            │
│ Display: standalone          : ✅                          │
│ Status                       : ✅ INSTALÁVEL              │
└───────────────────────────────────────────────────────────┘
```

## Anti-padrões

- ❌ Service Worker que cacheia POST/PUT (só GET)
- ❌ `skipWaiting()` sem confirmar (perde form em digitação)
- ❌ Pedir permissão de notification no load
- ❌ Manifest sem `purpose: maskable` (Android corta o ícone)
- ❌ Cachear API com `CacheFirst` (vê dado velho pra sempre)
- ❌ `start_url` que cai direto em login quando user já está logado
- ❌ Esquecer iOS — `beforeinstallprompt` não dispara, precisa tutorial

## Quando NÃO aplicar

- Projeto CLI / lib / API-only sem UI
- Landing page de evento (uso 1x, sem retorno)
- Site institucional estático (PWA é overkill — só meta tags básicas)
