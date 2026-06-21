---
name: video-streaming
category: frontend
module: 10
priority: P2
description: |
  Vídeo: HLS adaptive bitrate, transcoding pipeline (FFmpeg / Mux /
  Cloudflare Stream), WebRTC pra live, picture-in-picture, thumbnails,
  subtitles WebVTT, DRM se aplicável, bandwidth detection, lazy poster.
  Apps com vídeo pesado (cursos, social, telemedicina).
---

# Agent: video-streaming

## Missão

Vídeo é o conteúdo mais caro de servir e mais sensível a erro (buffer =
abandono). Este agente prescreve a stack moderna sem reinventar.

## Quando rodar

- Módulo 10 selecionado
- Detectado: `<video>`, `hls.js`, `mux`, `cloudflare-stream`, `livekit`, `mediasoup`
- Operador pediu "vídeo", "live streaming", "telemedicina"

## A. Stack default

| Caso | Stack |
|---|---|
| VOD curto (< 5min) | MP4 H.264, served via CDN |
| VOD longo / vários quality levels | HLS adaptive bitrate |
| Live broadcast (1:N) | HLS / DASH com latency 2-10s |
| Real-time interactive (videocall) | WebRTC (Mediasoup, Livekit, Daily.co) |
| Telemedicina HIPAA | Daily.co, Twilio (compliance certificado) |

## B. Transcoding

Original do user → várias qualities (240p, 480p, 720p, 1080p) + thumbnails.

| Tool | Quando |
|---|---|
| **FFmpeg** + worker | Self-hosted, custo CPU/GPU |
| **Mux** | Managed, ~$0.04/min processed |
| **Cloudflare Stream** | Managed, $5/1000 min + storage |
| **AWS MediaConvert** | All-in AWS |
| **Bunny Stream** | Cheap alternative |

```bash
# Transcoding básico FFmpeg
ffmpeg -i input.mp4 \
  -vf "scale=-2:720" -c:v libx264 -preset slow -crf 23 -c:a aac -b:a 128k \
  -f hls -hls_time 6 -hls_playlist_type vod -hls_segment_filename '720p_%03d.ts' \
  720p.m3u8
```

## C. HLS adaptive bitrate

```m3u8
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=400000,RESOLUTION=480x270
240p.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=1500000,RESOLUTION=854x480
480p.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=3500000,RESOLUTION=1280x720
720p.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=7000000,RESOLUTION=1920x1080
1080p.m3u8
```

Player escolhe quality conforme banda. Mude resolução sem reload.

## D. Player

```tsx
import Hls from 'hls.js';

useEffect(() => {
  if (Hls.isSupported()) {
    const hls = new Hls({
      maxBufferLength: 30,        // 30s buffer
      maxMaxBufferLength: 60,
      lowLatencyMode: false,
    });
    hls.loadSource(src);
    hls.attachMedia(videoRef.current);
  } else if (videoRef.current.canPlayType('application/vnd.apple.mpegurl')) {
    // Safari iOS — native HLS
    videoRef.current.src = src;
  }
}, [src]);
```

Lib pronta: **video.js**, **Plyr**, **Vidstack** (React).

## E. Lazy poster + preload

```html
<video poster="poster.jpg" preload="metadata" playsInline>
  <source src="video.m3u8" type="application/x-mpegURL">
</video>
```

`preload="metadata"`: só baixa metadata, não vídeo todo.
`playsInline`: iOS não fullscreen forçado.

## F. Subtitles WebVTT

```vtt
WEBVTT

00:00:00.000 --> 00:00:03.000
Olá, bem-vindo ao curso

00:00:03.500 --> 00:00:06.000
Hoje vamos falar sobre...
```

```html
<video>
  <source src="..." type="application/x-mpegURL">
  <track kind="subtitles" src="pt-BR.vtt" srclang="pt-BR" label="Português" default>
  <track kind="subtitles" src="en.vtt" srclang="en" label="English">
</video>
```

a11y obrigatória + ajuda SEO + tradução.

## G. Picture-in-Picture

```ts
videoRef.current.requestPictureInPicture();
```

Iconinho pra ativar. User vê vídeo enquanto navega outras telas.

## H. Live streaming (WebRTC)

```ts
// LiveKit (recomendado pra telemedicina/educação)
import { Room } from 'livekit-client';

const room = new Room();
await room.connect(LIVEKIT_URL, token);
await room.localParticipant.enableCameraAndMicrophone();
```

Latência: ~200ms (vs HLS 5-10s).

## I. DRM (se conteúdo pago)

- **Widevine** (Android, Chrome) — Google
- **FairPlay** (Apple Safari/iOS)
- **PlayReady** (Edge)

Implementar via EME (Encrypted Media Extensions). Complexo — use SaaS
(Mux, BuyDRM, EZDRM).

## J. Bandwidth detection

```ts
const connection = (navigator as any).connection;
if (connection?.effectiveType === '2g' || connection?.saveData) {
  // Servir poster + áudio só, ou qualidade mínima
}
```

## K. Métricas (QoS)

- Tempo até primeiro frame
- Buffer ratio (% do tempo travado)
- Bitrate médio
- Error rate
- View completion %

Mux/Cloudflare Stream dão tudo nativo.

## L. Greps

```bash
# <video> sem playsInline (iOS força fullscreen)
rg -n "<video" --type tsx | rg -v "playsInline"

# Sem poster
rg -n "<video" --type tsx | rg -v "poster"

# preload=auto (baixa vídeo todo desnecessário)
rg -n "preload=['\"]auto" --type tsx
```

## Output em sec.html

```
┌─ Video Streaming (Módulo 10) ────────────────────────────┐
│ VOD format                    : HLS adaptive bitrate    │
│ Qualities                     : 240/480/720/1080p ✅     │
│ Transcoding                   : Mux                      │
│ Player                        : Vidstack                 │
│ Lazy poster                   : ✅                        │
│ Subtitles WebVTT              : ✅ pt-BR + en-US         │
│ Picture-in-Picture            : ✅                        │
│ playsInline (iOS)             : ✅                        │
│ Bandwidth detection           : ✅ save-data respect     │
│ Live (WebRTC) — LiveKit       : ✅ (telemedicina)        │
│ Buffer ratio (p95)            : 2.1% ✅                  │
│ Time to first frame           : 1.4s ✅                  │
│ Status                        : ✅ STREAM-READY          │
└───────────────────────────────────────────────────────────┘
```

## Anti-padrões

- ❌ MP4 único em vez de HLS (não adapta a banda)
- ❌ Servir vídeo direto do S3 (egress caro, sem adaptive)
- ❌ `preload="auto"` (baixa vídeo todo, custo banda)
- ❌ Sem poster (tela preta enquanto carrega)
- ❌ Sem `playsInline` (iOS força fullscreen, quebra layout)
- ❌ Sem subtitles (a11y + SEO ruins)
- ❌ Live WebRTC sem TURN server (NAT bloqueia)
- ❌ Bitrate fixo (mobile com 3G trava)
- ❌ DRM caseiro (qualquer um craqueia)
- ❌ Sem métricas QoS (não sabe se user tem experiência boa)
- ❌ Vídeo > 720p em mobile (banda + bateria)
