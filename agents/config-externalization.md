---
name: config-externalization
category: cleanup
module: 12
priority: P1
description: |
  Nada de regra de negócio, copy, URL, limite, layout ou config no código.
  Tudo vai pra DB (mutável em runtime), arquivo de config (mutável em
  deploy), env var (mutável por ambiente) ou design tokens (mutável por
  brand). Bloqueia release se encontrar hardcode que deveria estar
  externalizado.
---

# Agent: config-externalization

## Missão

Aplicar a regra "nada no código" do operador. Código contém **lógica**;
configuração, regras de negócio, textos, limites, URLs, branding ficam
em camadas externas mutáveis sem deploy (DB) ou com 1 deploy mínimo (config
file). Resultado: trocar logo, ajustar limite, traduzir texto não exige
PR no código de negócio.

## Quando rodar

- Módulo 12 selecionado (sempre — mandatory)
- Complementa `mock-killer` (mock-killer remove; este externaliza)

## Hierarquia de "onde colocar"

| Tipo de valor | Onde mora | Quem altera | Tempo pra mudar |
|---|---|---|---|
| Secret / credencial | **ENV** + secret manager (Vault, AWS SM) | DevOps | rotação programada |
| Endpoint externo (URLs de API) | **ENV** por ambiente | DevOps | 1 deploy |
| Feature toggle | **DB** (`feature_flags`) ou serviço (LaunchDarkly, GrowthBook) | PM/ENG | tempo real |
| Limite/quota/timeout | **DB** (`settings` por tenant) ou config file | PM | tempo real ou 1 deploy |
| Regra de negócio variável | **DB** (tabelas de config) ou rules engine | PM | tempo real |
| Texto/copy/label | **i18n files** ou **CMS** | Marketing/PM | 1 deploy ou tempo real |
| Cores/fonts/spacing | **Design tokens** (JSON) ou **CSS vars** | Designer | 1 deploy |
| Layout/template de email | **DB** ou **CMS** | Marketing | tempo real |
| Workflow/pipeline | **DB** ou **YAML config** | PM | 1 deploy |

## Greps de caça (10 categorias)

### 1. Textos/copy hardcoded (deveria ir pra i18n/CMS)

```bash
# Strings em português dentro de tsx/jsx (não em test/storybook)
rg -n "[\"'](Olá|Bem-vindo|Salvar|Cancelar|Confirmar|Erro|Sucesso|Excluir)" \
   --type tsx --type jsx -g '!*.test.*' -g '!*.stories.*'

# Mensagens de erro hardcoded em backend
rg -n "throw new (Error|Exception)\([\"'][A-Za-zÀ-ú]{10,}" --type ts --type py
```

### 2. URLs/endpoints hardcoded (deveria ir pra ENV)

```bash
# https://... ou http://... não-localhost em código de produção
rg -n "https?://[a-z0-9.-]+\.[a-z]{2,}" --type ts --type js --type py \
   -g '!*.test.*' -g '!*.config.*' -g '!*.env*' -g '!node_modules'

# domínios em string literal
rg -n "['\"][a-z0-9-]+\.(com|net|io|app|dev|br)['\"]" --type ts --type js \
   -g '!*.test.*' -g '!node_modules'
```

### 3. Magic numbers (deveria ir pra constants ou DB)

```bash
# Números > 100 em literal (filtrar ruído depois)
rg -n "[^a-z_\$\.][0-9]{3,}[^0-9]" --type ts --type js \
   -g '!*.test.*' -g '!node_modules' -g '!*.snap'

# Times em ms / segundos hardcoded
rg -n "(setTimeout|setInterval)\([^,]+,\s*[0-9]+\)" --type ts --type js
```

### 4. Regras de negócio em código (deveria ir pra DB)

```bash
# Comissão / desconto / taxa hardcoded
rg -n "(commission|comissao|discount|desconto|tax|taxa|fee)\s*=\s*[0-9]" \
   --type ts --type py

# IF tenant === 'X' (regra por tenant — usar feature flag)
rg -n "(tenantId|tenant_id|tenant\.id)\s*===?\s*['\"][a-z0-9-]+['\"]" --type ts
```

### 5. Limites / quotas hardcoded

```bash
# MAX_X / LIMIT_X / threshold
rg -n "(MAX_[A-Z_]+|LIMIT_[A-Z_]+|MIN_[A-Z_]+)\s*=" --type ts --type py

# pageSize, perPage, batchSize hardcoded
rg -n "(pageSize|perPage|batchSize|chunkSize)\s*[:=]\s*[0-9]+" --type ts
```

### 6. Cores / espaçamentos / fonts em código (deveria ir pra tokens)

```bash
# Hex colors em componente
rg -n "#[0-9a-fA-F]{3,8}" --type tsx --type jsx --type css \
   -g '!**/tokens/**' -g '!**/theme/**' -g '!*.config.*'

# rgb/hsl em código
rg -n "(rgb|hsl)\(" --type tsx --type jsx -g '!**/tokens/**'

# px/rem hardcoded em styled-components ou similar
rg -n "padding:\s*['\"]?[0-9]+(px|rem)" --type tsx --type ts
```

### 7. Validações duplicadas (deveria ser schema único)

```bash
# Regex de email/CPF/telefone espalhados (deveria ser Zod/Yup schema central)
rg -n "/\^[^\/]*@[^\/]*\$/" --type ts --type js          # email regex
rg -n "[0-9]{3}\.[0-9]{3}\.[0-9]{3}-[0-9]{2}" --type ts  # CPF format
```

### 8. Templates de email/SMS no código (deveria ir pra DB/CMS)

```bash
# Strings com {{var}} ou ${var} fora de i18n/templates
rg -n "['\"]Olá \\\$\{|['\"]Caro \\\$\{|<p>.*\\\$\{" --type ts -g '!templates/'
```

### 9. Endpoints / rotas hardcoded no frontend

```bash
# fetch('/api/v1/...') espalhado (deveria ter API client centralizado)
rg -n "fetch\(['\"]/api" --type tsx --type ts | sort -u | head -20
```

### 10. Feature flags inline (`if (process.env.NEW_FEATURE)`)

```bash
# Feature flag direto em process.env (deveria ter flag service)
rg -n "process\.env\.[A-Z_]*FEATURE" --type ts --type js
rg -n "process\.env\.[A-Z_]*ENABLE" --type ts --type js
```

## Decisão por finding

| Tipo | Ação |
|---|---|
| Secret hardcoded | **CRIT** → mover pra ENV imediatamente + rotacionar |
| URL produção | Mover pra `process.env.X_URL` + `.env.example` |
| Magic number repetido | Constants file ou DB se variável por tenant |
| Regra de negócio (if tenant) | Feature flag ou coluna em `tenant_settings` |
| Texto em código | i18n key (`t('messages.welcome')`) ou CMS |
| Cor/spacing | Design token (`var(--color-primary)`) |
| Regex validação | Schema central (Zod/Yup) reusado em FE+BE |
| Template email | Tabela `email_templates` com `key`, `subject`, `body_html`, `body_text`, `locale` |
| Pagination size | DB setting com default, override por user |
| Feature flag inline | Sistema dedicado (LaunchDarkly/GrowthBook/Unleash/DB próprio) |

## Schema sugerido para tabelas de config

### `settings` (key-value tipado, por tenant)

```sql
CREATE TABLE settings (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid_v7(),
  tenant_id   UUID NOT NULL,
  key         TEXT NOT NULL,
  value       JSONB NOT NULL,
  type        TEXT NOT NULL CHECK (type IN ('string','number','boolean','json','array')),
  category    TEXT,              -- 'billing', 'ui', 'features', 'limits'
  description TEXT,
  default_value JSONB,
  updated_by  UUID,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, key)
);
```

### `feature_flags` (rollout gradual)

```sql
CREATE TABLE feature_flags (
  key             TEXT PRIMARY KEY,
  description     TEXT NOT NULL,
  enabled         BOOLEAN NOT NULL DEFAULT false,
  rollout_pct     SMALLINT NOT NULL DEFAULT 0 CHECK (rollout_pct BETWEEN 0 AND 100),
  enabled_tenants UUID[],         -- lista explícita override
  enabled_roles   TEXT[],         -- só ADMIN, etc
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at      TIMESTAMPTZ     -- flag temporário se vira dívida
);
```

### `email_templates`

```sql
CREATE TABLE email_templates (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid_v7(),
  key         TEXT NOT NULL,
  locale      CHAR(5) NOT NULL,   -- pt-BR, en-US
  subject     TEXT NOT NULL,
  body_html   TEXT NOT NULL,
  body_text   TEXT NOT NULL,
  variables   JSONB,              -- schema das variáveis aceitas
  version     INTEGER NOT NULL DEFAULT 1,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (key, locale)
);
```

### `design_tokens` (se design system dinâmico por tenant)

```json
// design-tokens/base.json
{
  "color": {
    "primary":   { "value": "#0066cc" },
    "secondary": { "value": "#666" },
    "success":   { "value": "#0a7d3d" }
  },
  "spacing": {
    "xs": { "value": "4px" },
    "sm": { "value": "8px" }
  }
}
```

Build script (Style Dictionary) gera CSS vars + Tailwind config + iOS/Android.

## Schema central de validação (DRY entre FE e BE)

```ts
// packages/shared/schemas/user.ts
import { z } from 'zod';

export const userSchema = z.object({
  email: z.string().email(),
  cpf:   z.string().regex(/^\d{11}$/),    // 1 fonte de verdade
  phone: z.string().regex(/^55\d{10,11}$/),
  age:   z.number().int().min(0).max(150)
});

export type User = z.infer<typeof userSchema>;
```

Importado por backend (NestJS/Express), frontend (React Hook Form) e
geração de OpenAPI. Mudança em 1 lugar propaga.

## Output esperado em sec.html

```
┌─ Config Externalization (Módulo 12) ─────────────────────┐
│ Textos hardcoded em código   : 0 ✅ (era 247 → i18n)      │
│ URLs hardcoded               : 0 ✅ (3 movidos pra ENV)   │
│ Magic numbers                : 5 (acordados em PR)         │
│ Cores em componente          : 0 ✅ (47 → design tokens)  │
│ Regex duplicado FE/BE        : 0 ✅ (12 → schema central) │
│ Email templates em código    : 0 ✅ (8 → DB)              │
│ Feature flags inline         : 0 ✅ (5 → tabela flags)    │
│ Regras de negócio "if tenant": 0 ✅ (2 → settings)        │
│ .env.example sincronizado    : ✅ 23/23 vars cobertas     │
│ Schema validação central     : ✅ shared/schemas/*        │
│ Status                       : ✅ EXTERNALIZED            │
└───────────────────────────────────────────────────────────┘
```

## Anti-padrões (NUNCA)

- ❌ `const TAX_RATE = 0.1` (deveria ser config por região/tenant)
- ❌ `if (tenant.id === 'super-cliente-x') { ...código diferente... }`
- ❌ Texto português em código frontend (i18n key)
- ❌ Email/SMS body em string template no código
- ❌ Regex de validação duplicado em FE e BE
- ❌ Cor em hex no JSX (design token + CSS var)
- ❌ URL produção em string literal
- ❌ Feature flag em `if (process.env.NEW_X)` (sistema dedicado)
- ❌ `.env.example` desincronizado com uso real
- ❌ Segredo em `config.ts` (env + secret manager)

## Intelligence (⭐ v0.20) — magic numbers que NÃO são "magic"

Lê `.blindar/intelligence.yml`:

```yaml
config-externalization:
  whitelist_constants:
    # Códigos HTTP universais
    - [100, 200, 201, 204, 301, 302, 304, 400, 401, 403, 404, 409, 422, 429, 500, 502, 503]
    # Bytes/sizes universais
    - [1024, 4096, 8192, 16384, 32768, 65536, 1048576]
    # Tempos universais (ms, s)
    - [0, 1, 10, 100, 1000, 5000, 30000, 60000, 86400]
    # Math/percent universais
    - [0.5, 0.1, 0.05, 0.01]

  whitelist_url_patterns:
    # URLs internas / localhost OK em config files
    - "localhost"
    - "127.0.0.1"
    - "0.0.0.0"
    - "*.local"
    - "*.test"
    - "example.com"           # exemplo legítimo em docs

  whitelist_strings_short:
    # Strings de 1-3 chars que NÃO são copy
    - "ok", "id", "OK", "ID", "GB", "MB", "KB", "px", "rem", "%", "#"

  inline_override_marker: "// @blindar:hardcode-ok"
```

### Quando hardcoded É correto

```ts
// @blindar:hardcode-ok -- limite técnico do JWT spec
const JWT_MAX_LENGTH = 8192;

// @blindar:hardcode-ok -- constante matemática
const MILLISECONDS_PER_DAY = 86_400_000;

// @blindar:hardcode-ok -- código HTTP padrão
if (res.status === 429) backoff();
```

Sem precisar de override:
- Variáveis em test files
- Constantes em `**/*.config.ts`, `*.config.js`
- Valores em arquivo `**/constants.ts` (já externalizou pra um arquivo, não precisa ir pra DB)
- `process.env.X` em código (já está em env)

### Auto-detecção de "regra de negócio variável"

Sinais de que algo PRECISA externalizar:
- Mesmo valor aparece em 3+ lugares (DRY)
- Valor comentado "ajustar conforme cliente"
- `if (tenantId === 'X')` (regra por tenant)
- Diferença entre `prod` e `dev` no mesmo valor (deve ser env)

## Interação com outros agentes

- **mock-killer** (mesmo módulo 12) remove `console.log`/TODO/mock — este externaliza hardcodes legítimos. Coordenar pra não duplicar findings.
- **i18n-tz** consome saída deste agente (textos identificados aqui viram chaves i18n).
- **db-architect** valida os schemas das tabelas de config (`settings`, `feature_flags`, `email_templates`).
- **auth-premium** valida que `pinAttempts`, `idleTimeoutMinutes` etc são configuráveis em `settings`, não hardcoded.
