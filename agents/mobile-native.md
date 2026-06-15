---
name: mobile-native
category: frontend
module: 10
priority: P2
description: |
  Mobile além de PWA: React Native + Expo (SDK 52+) ou Flutter. Cobre
  deep links + universal links, push nativo (FCM/APNs), app shortcuts,
  CodePush/EAS Update pra deploy OTA, App Store / Play Console
  submission, signing, screenshots por device, tests em emulador real.
---

# Agent: mobile-native

## Missão

Quando PWA não basta (acesso à câmera nativa avançada, Bluetooth,
HealthKit, biometria nativa, app store credibility), vai pra nativo.
Este agente prescreve a stack mínima moderna sem ter que reaprender
toda semana.

## Quando rodar

- Módulo 10 selecionado
- Detectado: `expo`, `react-native`, `flutter`, `capacitor`
- Operador pediu "app store", "Play Store", "iOS app", "Android nativo"

## A. Stack default 2026

| Camada | Escolha |
|---|---|
| Framework | **Expo SDK 52** (React Native + tooling completo) |
| Routing | Expo Router v3 (file-based, igual Next.js) |
| State | Same que web — Zustand/Jotai + TanStack Query |
| Build | EAS Build (managed, sem precisar de Xcode local) |
| OTA Update | **EAS Update** (substitui CodePush, descontinuado) |
| Push | Expo Push (wrapper de FCM+APNs) ou direto via libs |
| Storage | AsyncStorage + SecureStore (keychain/keystore) |
| Testes | Jest + Detox (E2E em device real) |

Alternativa: **Flutter 3** se time já domina ou quer animações ricas.

## B. Deep links + Universal links

```ts
// app.json
{
  "expo": {
    "scheme": "salonpro",
    "ios": {
      "associatedDomains": ["applinks:salonpro.com"]
    },
    "android": {
      "intentFilters": [{
        "action": "VIEW",
        "data": [{ "scheme": "https", "host": "salonpro.com", "pathPrefix": "/appointments" }],
        "category": ["BROWSABLE", "DEFAULT"],
        "autoVerify": true
      }]
    }
  }
}
```

Web hospeda `apple-app-site-association` e `assetlinks.json` em
`/.well-known/`. Link `https://salonpro.com/appointments/abc` abre direto
no app instalado.

## C. Push nativo (Expo wrapper)

```ts
import * as Notifications from 'expo-notifications';

async function registerForPush() {
  const { status } = await Notifications.getPermissionsAsync();
  if (status !== 'granted') {
    const { status: newStatus } = await Notifications.requestPermissionsAsync();
    if (newStatus !== 'granted') return null;
  }
  const token = (await Notifications.getExpoPushTokenAsync({
    projectId: 'your-eas-project-id'
  })).data;
  await fetch('/api/push/register', { method: 'POST', body: JSON.stringify({ token, platform: Platform.OS }) });
}
```

Backend usa Expo Push API (envia pra FCM e APNs internamente).

## D. App shortcuts (long-press no ícone)

```json
// app.json
{
  "expo": {
    "ios": {
      "config": {
        "shortcuts": [
          { "type": "newAppointment", "title": "Novo agendamento", "subtitle": "Criar rápido", "icon": "calendar" }
        ]
      }
    }
  }
}
```

Android: via `Linking.addEventListener` + intent.

## E. OTA Update (EAS Update)

Push bug fix sem App Store review (limitado a JS, não pode mudar nativo).

```bash
# Deploy de bug fix em 5min, sem review
eas update --branch production --message "Fix: race condition em login"
```

Sempre ter:
- Channel por ambiente (dev/staging/prod)
- Rollback automático se crash rate sobe > 1%
- Force update pra mudanças críticas

## F. EAS Build (sem Mac local)

```bash
# Build iOS na nuvem
eas build --platform ios --profile production

# Submit pra App Store
eas submit --platform ios --latest
```

Sem Xcode, sem certs locais, sem dor de cabeça.

## G. Permissions com explicação ANTES

```ts
// Errado: pede permissão sem contexto
await Camera.requestPermissionsAsync();

// Certo: explica primeiro, deixa user decidir
function CameraPermissionGate({ children }) {
  const [showRationale, setShowRationale] = useState(false);
  if (showRationale) {
    return (
      <View>
        <Text>Pra tirar foto do cliente antes do serviço, precisamos da câmera.</Text>
        <Button onPress={async () => {
          await Camera.requestPermissionsAsync();
          setShowRationale(false);
        }} title="Permitir acesso à câmera" />
        <Button variant="ghost" onPress={() => setShowRationale(false)} title="Agora não" />
      </View>
    );
  }
  return children;
}
```

iOS exige `NSCameraUsageDescription` no Info.plist com texto descritivo.

## H. Biometria nativa

```ts
import * as LocalAuthentication from 'expo-local-authentication';

const result = await LocalAuthentication.authenticateAsync({
  promptMessage: 'Entre com biometria',
  fallbackLabel: 'Usar senha',
});
if (result.success) await unlockWithBiometric();
```

iOS: FaceID/TouchID. Android: fingerprint/face unlock.

## I. SecureStore (NÃO AsyncStorage pra tokens)

```ts
import * as SecureStore from 'expo-secure-store';

// Refresh token vai pro keychain/keystore (criptografado, secure enclave)
await SecureStore.setItemAsync('refresh_token', token);
const token = await SecureStore.getItemAsync('refresh_token');
```

AsyncStorage é plaintext em arquivo — NUNCA secrets.

## J. Testes E2E (Detox)

```ts
describe('Login flow', () => {
  beforeAll(async () => { await device.launchApp(); });
  it('faz login e abre dashboard', async () => {
    await element(by.id('email-input')).typeText('test@local');
    await element(by.id('password-input')).typeText('@Teste123');
    await element(by.id('login-btn')).tap();
    await expect(element(by.id('dashboard'))).toBeVisible();
  });
});
```

Roda em iOS Simulator + Android Emulator em CI (GitHub Actions com macOS runner).

## K. Submission

- **iOS**: TestFlight pra beta, App Store Connect pra prod. Review leva 24-48h.
- **Android**: Internal Testing → Closed Testing → Open Testing → Production. Mais permissivo.

Screenshots gerados via Fastlane Snapshot (5.5", 6.5", 6.7" iPhones + iPad).

## L. Greps

```bash
# Token em AsyncStorage (CRIT — plaintext)
rg -n "AsyncStorage\.setItem.*token" --type ts

# Permission sem rationale
rg -nB 5 "requestPermissionsAsync" --type ts | rg -v "(Modal|rationale|Text)"

# console.log em produção
rg -n "console\.log" --type ts -g '!*.test.*' -g '!*.dev.*'

# Deep link sem signed verification
rg -n "Linking\.addEventListener" --type ts -A 5 | rg -v "verify|allowList"
```

## Output em sec.html

```
┌─ Mobile Native (Módulo 10) ──────────────────────────────┐
│ Framework                     : Expo SDK 52              │
│ Deep links + universal links  : ✅                        │
│ App shortcuts                 : ✅                        │
│ Push nativo (Expo Push)       : ✅                        │
│ Biometria (FaceID/fingerprint): ✅                        │
│ SecureStore p/ tokens         : ✅ (não AsyncStorage)    │
│ EAS Update (OTA)              : ✅ rollback < 1% crash   │
│ EAS Build (sem Xcode local)   : ✅                        │
│ Detox E2E (iOS+Android)       : ✅ green                  │
│ Submission ready              : ✅                        │
│ Screenshots                   : 5 devices × 2 stores      │
│ Status                        : ✅ STORE-READY           │
└───────────────────────────────────────────────────────────┘
```

## Anti-padrões

- ❌ Token em `AsyncStorage` (plaintext, qualquer app no device lê)
- ❌ Pedir permissão sem rationale prévia (user nega pra sempre)
- ❌ Deep link sem `autoVerify` (qualquer app intercepta)
- ❌ Build local sem CI (mac de 1 dev quebrou = todo mundo trava)
- ❌ OTA Update sem rollback automático (push bug, app fica zumbi)
- ❌ Esquecer `Info.plist` privacy descriptions (iOS rejeita)
- ❌ Tamanho do bundle > 50MB (Android desinstala em low storage)
- ❌ Sem TestFlight beta antes de prod
- ❌ `console.log` em prod (vaza dado em Charles Proxy)
- ❌ Permissão de localização sempre (use só when-in-use)
- ❌ Screenshots desatualizados na store (rejeita review)
