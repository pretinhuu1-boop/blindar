---
name: audio-voice
category: frontend
module: 10
priority: P2
description: |
  Apps com áudio/voz: STT (Whisper/Deepgram), TTS (ElevenLabs/Azure),
  voice commands, gravação no browser (MediaRecorder), PTT (push-to-
  talk no WhatsApp), permission UX, áudio compression OPUS, transcrição
  com diarization, voiceprint privacy.
---

# Agent: audio-voice

## Missão

Áudio errado = arquivo gigante, permission negada permanente, transcrição
horrível em sotaque brasileiro. Este agente prescreve a stack correta.

## Quando rodar

- Módulo 10 selecionado
- Detectado: `MediaRecorder`, `WebRTC`, `wavesurfer`, `whisper`, `deepgram`, `elevenlabs`
- Operador pediu "voz", "áudio", "transcrição", "TTS"

## A. Gravação no browser

```ts
const stream = await navigator.mediaDevices.getUserMedia({ audio: {
  echoCancellation: true,
  noiseSuppression: true,
  autoGainControl: true,
  sampleRate: 48000,
} });

const recorder = new MediaRecorder(stream, {
  mimeType: 'audio/webm;codecs=opus',     // Opus = melhor compressão
  audioBitsPerSecond: 32_000,              // 32kbps voz limpa
});
const chunks: Blob[] = [];
recorder.ondataavailable = e => chunks.push(e.data);
recorder.onstop = async () => {
  const blob = new Blob(chunks, { type: 'audio/webm;codecs=opus' });
  await upload(blob);
};
recorder.start(250);   // chunk a cada 250ms
```

### Permission UX

NUNCA pedir `getUserMedia` no load. Pedir após click do user.

### iOS Safari

Mais restritivo. Só funciona com:
- `HTTPS` (sempre)
- User gesture (click direto)
- `playsInline` em `<audio>`

## B. PTT (push-to-talk) — WhatsApp pattern

```ts
const btn = document.getElementById('mic');
btn.addEventListener('pointerdown', startRecording);
btn.addEventListener('pointerup', stopRecording);
btn.addEventListener('pointerleave', stopRecording);   // soltou fora = cancela

// Mostrar waveform live (Web Audio API analyser)
```

Para integrar com Evolution API (WhatsApp), salvar `.ogg` com flag PTT.
Ver playbook `whatsapp-evolution-api.md`.

## C. STT (Speech-to-Text)

| Provider | Quando |
|---|---|
| **Whisper API** (OpenAI) | Default. Bom em pt-BR, US$0.006/min |
| **Whisper self-hosted** | Privacidade, volume alto |
| **Deepgram** | Streaming + diarization + barato |
| **Azure Speech** | Enterprise + dialects |
| **AssemblyAI** | Speaker labels, summarization |
| **Google Speech** | Streaming + multi-língua |

Streaming (transcrição em tempo real):
```ts
const ws = new WebSocket('wss://api.deepgram.com/v1/listen?language=pt-BR&punctuate=true&diarize=true');
recorder.ondataavailable = e => ws.send(e.data);
ws.onmessage = e => updateTranscript(JSON.parse(e.data).channel.alternatives[0].transcript);
```

## D. TTS (Text-to-Speech)

| Provider | Quando |
|---|---|
| **ElevenLabs** | Qualidade top, voice cloning |
| **Azure TTS** | Vozes naturais em pt-BR |
| **AWS Polly** | Standard, barato |
| **Browser nativo** | Free mas qualidade ruim |

```ts
const audio = await fetch('https://api.elevenlabs.io/v1/text-to-speech/voice-id', {
  method: 'POST',
  body: JSON.stringify({ text, model_id: 'eleven_multilingual_v2' })
});
new Audio(URL.createObjectURL(await audio.blob())).play();
```

## E. Voice commands

```ts
const recognition = new SpeechRecognition();
recognition.lang = 'pt-BR';
recognition.continuous = false;
recognition.onresult = e => {
  const cmd = e.results[0][0].transcript.toLowerCase();
  if (cmd.match(/criar agendamento/)) navigateTo('/appointments/new');
};
```

Browser nativo grátis mas só Chrome. Pra cross-browser, usar Deepgram
streaming.

## F. Compression & storage

| Codec | Quando |
|---|---|
| **Opus** | Default voz (32kbps suficiente, melhor qualidade/byte) |
| **AAC** | Compatibilidade iOS/Safari |
| **MP3** | Legacy |
| **WAV** | Master / processamento — gigante (não pra storage) |

Pra reduzir:
- 16kHz sample rate pra voz (suficiente)
- Mono (não stereo)
- VBR (variable bitrate)

## G. Privacy

- Voiceprint é PII (LGPD) — consent explícito
- Audio file vai criptografado at-rest
- Transcrição é PII também
- Deletar áudio após N dias se não precisa (só transcrição)

## H. Greps

```bash
# getUserMedia sem click prévio
rg -nB 10 "getUserMedia\\(\\{ audio" --type ts | rg -v "onClick|addEventListener"

# Áudio WAV em produção (gigante)
rg -n "audio/wav" --type ts

# Token de provider hardcoded
rg -n "(elevenlabs|deepgram|whisper).*[A-Za-z0-9]{20,}" --type ts
```

## Output em sec.html

```
┌─ Audio / Voice (Módulo 10) ──────────────────────────────┐
│ Recording (MediaRecorder)     : ✅ Opus 32kbps           │
│ Permission UX (após click)    : ✅                        │
│ Echo cancel + noise suppress  : ✅                        │
│ PTT (push-to-talk)            : ✅                        │
│ STT provider                  : Deepgram streaming pt-BR │
│ TTS provider                  : ElevenLabs multilingual  │
│ Diarization (speakers)        : ✅                        │
│ Compression (Opus)            : ✅ ~250KB/min            │
│ Storage cifrado at-rest       : ✅                        │
│ Consent gravação              : ✅                        │
│ Retenção configurável         : 30 dias                  │
│ Status                        : ✅ VOICE-READY           │
└───────────────────────────────────────────────────────────┘
```

## Anti-padrões

- ❌ getUserMedia no load (perde permissão pra sempre)
- ❌ WAV em storage (10x maior que Opus)
- ❌ Stereo pra gravação de voz (dobra tamanho sem ganho)
- ❌ Sample rate 48kHz pra fala (16kHz suficiente)
- ❌ Áudio em texto sem cifragem (PII vazada)
- ❌ Voice command sempre escutando sem indicação visual
- ❌ Sem feedback de gravação (user não sabe se gravou)
- ❌ Sem fallback se mic permission negado
- ❌ TTS browser nativo em produto pago (qualidade ruim)
- ❌ Token de provider no client
