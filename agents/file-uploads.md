---
name: file-uploads
category: security
module: 2
priority: P0
description: |
  Upload de arquivo é vetor #1 subestimado de RCE/XSS. Cobre: presigned
  URL (upload direto pro storage, backend não vê bytes), antivírus
  obrigatório (ClamAV/VirusTotal), MIME validation por magic bytes (não
  extensão), strip de EXIF/metadata, image re-encoding (SVG é vetor XSS),
  signed URL de leitura com expiração, anti-hotlink, lifecycle de cleanup.
---

# Agent: file-uploads

## Missão

Upload mal feito = RCE (executar código no servidor), XSS (SVG malicioso),
PII leak (foto com geolocation), DDoS de storage (custo infinito).
Este agente prescreve o pipeline seguro de upload.

## Quando rodar

- Módulo 2 selecionado E projeto aceita upload de arquivo
- Detectado: `multer` / `formidable` / `busboy` / `aws-sdk s3` / `multipart`
- Operador pediu "upload", "avatar", "foto", "documento"

## A. Presigned URL (upload direto, backend não toca bytes)

### Padrão certo

```
Cliente               Backend              S3/R2/MinIO
   |                     |                     |
   |--1. solicita upload-->|                     |
   |                     |--2. valida tipo,    |
   |                     |    tamanho, user    |
   |                     |    gera URL signed--|
   |<--3. URL + fields----|                     |
   |--4. PUT direto ao storage---------------->|
   |                     |<--5. callback-------|
   |                     |  (S3 event/webhook) |
   |                     |--6. move temp/→final|
   |                     |    + DB.create      |
```

### Backend (NestJS / Express)

```ts
@Post('uploads/sign')
async sign(@Body() dto: { filename, contentType, sizeBytes }, @Req() req) {
  // 1. Valida user/quota
  const usage = await getUsage(req.user.id);
  if (usage + dto.sizeBytes > userQuota(req.user.plan)) {
    throw new TooManyRequests('quota_exceeded');
  }

  // 2. Valida tipo declarado (extensão + content-type)
  const ALLOWED = ['image/jpeg', 'image/png', 'image/webp', 'application/pdf'];
  if (!ALLOWED.includes(dto.contentType)) throw new BadRequest('mime_not_allowed');
  if (dto.sizeBytes > 25 * 1024 * 1024) throw new BadRequest('too_large');

  // 3. Key seguro (não confiar em filename do cliente)
  const ext = mime.extension(dto.contentType);
  const key = `temp/${req.user.tenantId}/${randomUUID()}.${ext}`;

  // 4. Gera presigned com restrições
  const url = await s3.getSignedUrl('putObject', {
    Bucket: 'uploads',
    Key: key,
    Expires: 300,                     // 5min
    ContentType: dto.contentType,     // força o tipo declarado
    ContentLength: dto.sizeBytes,     // não aceitar arquivo maior
    Conditions: [
      ['content-length-range', 0, 25 * 1024 * 1024]
    ]
  });

  return { url, key, expiresIn: 300 };
}
```

### Por que melhor que upload via backend

- Backend não precisa receber bytes (memória/CPU)
- S3 valida tipo e tamanho automaticamente
- Atacante não consegue mandar > size limit
- Escala melhor (storage absorve carga)

## B. Validação por magic bytes (não confiar em extensão)

```ts
import { fileTypeFromBuffer } from 'file-type';

@Post('uploads/finalize')
async finalize(@Body() { key }, @Req() req) {
  // Baixa primeiros 4KB pra detectar tipo real
  const head = await s3.getObject({ Bucket: 'uploads', Key: key, Range: 'bytes=0-4096' });
  const detected = await fileTypeFromBuffer(head.Body);

  if (!detected) throw new BadRequest('file_type_undetectable');

  const ALLOWED_MAGIC = ['jpg','png','webp','pdf','gif'];
  if (!ALLOWED_MAGIC.includes(detected.ext)) {
    await s3.deleteObject({ Bucket: 'uploads', Key: key });
    throw new BadRequest(`file_type_disallowed: ${detected.ext}`);
  }
  // ... segue
}
```

**Importante:** atacante pode upload `evil.jpg` que na verdade é PHP/HTML/JS.
Magic bytes (primeiros bytes do arquivo) revelam tipo real.

## C. Antivírus obrigatório

```ts
// Opção 1: ClamAV self-hosted
import { NodeClam } from 'clamscan';
const clamscan = await new NodeClam().init({ /* ... */ });

const { isInfected, viruses } = await clamscan.scanStream(s3Stream);
if (isInfected) {
  await s3.deleteObject({ ... });
  await audit.log({ type: 'malware_blocked', viruses, userId: req.user.id });
  throw new UnprocessableEntity('file_infected');
}

// Opção 2: VirusTotal API (limite gratuito)
// Opção 3: AWS GuardDuty Malware Protection for S3 (managed)
```

Sem AV é loteria — basta um malware passar pra você virar **vetor de distribuição**
(usuários baixam → reputação queima).

## D. Image processing (strip + re-encode)

```ts
import sharp from 'sharp';

// Para CADA imagem aceita:
// 1. Strip metadata (EXIF: geolocation, device, timestamp)
// 2. Re-encode (mata SVG injection, polyglot)
// 3. Limita dimensões (anti-zip bomb)

const processed = await sharp(buffer, { failOnError: true, limitInputPixels: 25_000_000 })
  .rotate()                         // auto-rotate via EXIF antes de strip
  .resize({ width: 2000, height: 2000, fit: 'inside', withoutEnlargement: true })
  .toFormat('webp', { quality: 85 })
  .withMetadata({ exif: undefined }) // remove EXIF
  .toBuffer();
```

### SVG é ESPECIAL

```ts
// SVG pode conter <script>, <foreignObject>, event handlers
import DOMPurify from 'isomorphic-dompurify';

if (mime === 'image/svg+xml') {
  const cleaned = DOMPurify.sanitize(svgString, {
    USE_PROFILES: { svg: true, svgFilters: true },
    FORBID_TAGS: ['script', 'foreignObject'],
    FORBID_ATTR: ['onerror', 'onload', 'onclick']
  });
  // Se diff significativo, rejeitar (tinha código)
  if (cleaned.length / svgString.length < 0.7) throw new BadRequest('svg_suspicious');
}
```

## E. Storage organizado

```
uploads/
├── temp/<tenant>/<uuid>.ext       # 24h TTL, se não promovido = delete
├── avatars/<user>/<uuid>.webp     # signed URL 7 dias
├── documents/<tenant>/<uuid>.pdf  # signed URL 1h
└── public/<filename>              # CDN cache 1 ano

archive/                            # após delete soft, 30 dias antes do hard delete
```

### Lifecycle policies (S3/R2)

```json
{
  "Rules": [
    { "Prefix": "temp/", "Expiration": { "Days": 1 } },
    { "Prefix": "archive/", "Expiration": { "Days": 30 } },
    { "Prefix": "audit/", "Transitions": [{ "Days": 90, "StorageClass": "GLACIER" }] }
  ]
}
```

## F. Signed URL de leitura (conteúdo privado)

```ts
// Nada de URL pública pra dado de user
@Get('files/:id')
async getUrl(@Param('id') id, @Req() req) {
  const file = await db.file.findUnique({ where: { id, tenant_id: req.user.tenantId } });
  if (!file) throw new NotFound();

  // Verifica permissão (RLS já filtrou por tenant, mas confirmar)
  if (!canAccess(req.user, file)) throw new Forbidden();

  const url = await s3.getSignedUrl('getObject', {
    Bucket: file.bucket, Key: file.key,
    Expires: 900,                   // 15min
    ResponseContentDisposition: `attachment; filename="${sanitize(file.original_name)}"`
  });

  await audit.log({ type: 'file_download_url', fileId: id, userId: req.user.id });
  return { url, expiresIn: 900 };
}
```

## G. Anti-hotlink (banda alheia)

```ts
// Imagem servida com Referer check (Cloudflare/Nginx)
// OU: signed URL sempre (recomendado)
// OU: rate limit por IP em /files/:id (cliente legítimo cacheia)
```

## H. Quota por user/tenant

```sql
CREATE TABLE storage_usage (
  tenant_id      UUID PRIMARY KEY,
  bytes_used     BIGINT NOT NULL DEFAULT 0,
  bytes_limit    BIGINT NOT NULL,
  files_count    INTEGER NOT NULL DEFAULT 0,
  files_limit    INTEGER NOT NULL,
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

Atualizar com transaction ao criar/deletar. Bloquear upload se exceder.

## I. Greps obrigatórios

```bash
# Upload direto multipart no backend (deveria ser presigned)
rg -n "multer|formidable|busboy" --type ts --type js -g '!*.test.*'

# MIME validado por extensão (inseguro)
rg -n "extension|\.jpg|\.png" --type ts -B 2 | rg -i "(allow|valid|check)"

# Sem strip de EXIF
rg -n "sharp\(" --type ts | rg -v "withMetadata"

# SVG aceito sem sanitize
rg -n "(image/svg|\.svg)" --type ts | rg -v "DOMPurify|sanitize"

# URL pública pra dado privado
rg -n "s3\..*public-read|ACL.*public" --type ts

# Sem antivírus
rg -n "clamscan|clamav|VirusTotal" --type ts || echo "⚠ Nenhum AV detectado"
```

## Output esperado em sec.html

```
┌─ File Uploads (Módulo 2) ────────────────────────────────┐
│ Presigned URL (não-proxy)     : ✅                         │
│ MIME por magic bytes          : ✅ file-type lib          │
│ Size cap                      : ✅ 25MB                    │
│ Antivírus (ClamAV)            : ✅                         │
│ EXIF strip + re-encode        : ✅ sharp                   │
│ SVG sanitize (DOMPurify)      : ✅                         │
│ Signed URL leitura (15min)    : ✅                         │
│ Lifecycle policies            : ✅ temp/24h, archive/30d   │
│ Quota por user                : ✅ tabela storage_usage   │
│ Anti-hotlink                  : ✅ signed URL              │
│ Audit log upload+download     : ✅                         │
│ Status                        : ✅ HARDENED               │
└───────────────────────────────────────────────────────────┘
```

## Anti-padrões (alguns CRIT)

- ❌ Upload via backend multer sem presigned (memory pressure + DoS)
- ❌ Validar MIME só por extensão (`.jpg` pode ser PHP)
- ❌ Sem antivírus em upload público
- ❌ Servir SVG raw (XSS via `<script>` no SVG)
- ❌ Salvar EXIF (vaza geolocation, device)
- ❌ Filename do user vira key (`../../etc/passwd`)
- ❌ Sem `ContentLength` no presigned (atacante manda 10GB)
- ❌ Bucket público (`ACL: public-read` em dado privado)
- ❌ URL eterna pra dado privado (deveria expirar)
- ❌ Sem quota (1 user enche bucket inteiro)
- ❌ Sem lifecycle (temp/ cresce eterno)
- ❌ Re-encode com qualidade 100% (perde benefício de compressão)
