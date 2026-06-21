---
name: content-quality
category: content
module: 12
priority: P1
description: |
  Revisa gramática, ortografia, pontuação, concordância, tom de voz e
  consistência terminológica de TODO texto visível ao usuário (UI,
  emails, documentos legais, mensagens de erro, microcopy). Respeita
  config de tom do projeto (formal/casual, você/tu, glossário) gravada
  em `.blindar/copy-style.yml`. Bloqueia release se erros crit (ortografia
  em produção) ou inconsistência grave de tom/glossário.
---

# Agent: content-quality

## Missão

Texto ruim = produto ruim mesmo se código está perfeito. Erro de
concordância no botão primário, glossário inconsistente ("agendamento" /
"reserva" / "marcação" misturados), tom hostil em mensagem de erro =
queima de credibilidade. Este agente garante texto **correto, consistente
e no tom certo**.

## Quando rodar

- Módulo 12 selecionado (sempre — mandatory)
- Detectado: arquivos i18n (`locales/*`, `messages/*`, `lang/*`), templates
  de email, copy de UI

## A. Config de tom (`.blindar/copy-style.yml`)

O **operador define** o tom do projeto **uma vez**, e este agente valida
contra isso em cada round. Config tem **4 listas de proteção** pra evitar
flagar marcas, nomes próprios, termos técnicos consagrados e
code-switching intencional.

```yaml
# .blindar/copy-style.yml — gerado no launcher ou criado manual
language_primary: pt-BR
languages_supported: [pt-BR, en-US]

# ─── PROTECTED TERMS (NUNCA flagados, nunca traduzidos) ───
protected_terms:
  # Marcas e produtos (auto-detect via package.json, README, ENV vars)
  - "Salon Pro"
  - "Beleza Real"             # nome de salão (tenant)
  - "Stripe"
  - "Mercado Pago"
  - "WhatsApp"
  - "Evolution API"
  - "Vercel"
  - "Cloudflare"
  - "Supabase"
  - "PostgreSQL"
  - "Next.js"
  # Nomes de pessoas (extrair de team.json ou config)
  - "Maykonbts"
  - "Ana"
  # Nomes de roles/features do produto (do role-hierarchy template)
  - "MASTER"
  - "ADMIN"
  - "GERENCIAL"
  - "OPERACIONAL"

# ─── TECHNICAL TERMS (aceitos em qualquer idioma, code-switching OK) ───
technical_terms:
  # Termos universais de dev/tech — não traduzir, não flagar
  - "API"
  - "webhook"
  - "deploy"
  - "dashboard"
  - "frontend"
  - "backend"
  - "framework"
  - "endpoint"
  - "token"
  - "log"
  - "cache"
  - "queue"
  - "feature"
  - "feature flag"
  - "rollout"
  - "kill switch"
  # Métricas/business
  - "KPI"
  - "ROI"
  - "MVP"
  - "SaaS"
  - "MRR"
  - "churn"
  - "lead"
  - "funnel"
  - "onboarding"
  # Web/UX
  - "scroll"
  - "swipe"
  - "drag and drop"
  - "responsive"

# ─── PROPER NOUNS PATTERN (auto-detecção) ───
proper_nouns_detection:
  # Padrões que indicam nome próprio (não revisar ortografia)
  rules:
    - "CamelCase ≥ 2 capitalizadas seguidas"        # "WhatsApp", "PayPal"
    - "Tudo MAIÚSCULO ≥ 2 chars"                     # "API", "CEO", "PIN"
    - "Termo com @ no início"                        # "@maykonbts"
    - "Início de frase mas precedido de 'do/da/de'"  # "do Stripe", "da Vercel"
  auto_extract_from:
    - "package.json"           # name, author
    - "README.md"              # H1, repeated capitalized
    - ".env.example"           # SERVICE_NAME, BRAND_NAME
    - "src/lib/brand.ts"       # design tokens

# ─── ALLOWED CODE-SWITCHING (mistura intencional pt+en) ───
allowed_code_switching:
  # Padrões aceitos no copy do produto (não vira erro de purismo)
  allow_in_pt_text:
    - "Configurar [termo técnico]"     # "Configurar webhook"
    - "Ativar [termo técnico]"          # "Ativar feature flag"
    - "Conectar [marca]"                # "Conectar Stripe"
    - "Sincronizar com [marca]"
  forbidden_translations:
    # NÃO traduzir mesmo se LanguageTool sugerir
    - "deploy": "implantação"           # mantém "deploy"
    - "webhook": "gancho web"           # mantém "webhook"
    - "dashboard": "painel"             # aceita ambos, mas prefere o original do projeto

tone:
  formality: casual            # casual | neutral | formal
  pronoun_pt: você              # você | tu | vocês
  warmth: friendly              # friendly | neutral | direct
  emoji_in_ui: false
  exclamation_max_per_screen: 1
  reading_level: 8              # grade level (ensino fundamental)

glossary:
  # Termo preferido → variações proibidas (consistência interna do produto)
  "agendamento": ["reserva", "marcação", "appointment"]
  "cliente":     ["customer", "freguês", "consumidor"]
  "salão":       ["estabelecimento", "loja", "shop"]
  "profissional":["funcionário", "colaborador", "staff"]
  "serviço":     ["procedimento", "trabalho", "service"]
  "PIN":         ["senha curta", "código de acesso"]

forbidden_words:
  # Palavras que NUNCA podem aparecer em UI/produto
  - "erro fatal"        # use "algo deu errado"
  - "usuário inválido"  # use "não foi possível encontrar essa conta"
  - "permissão negada"  # use "você não tem acesso a isso"
  - "deletar"           # use "excluir"

preferred_phrasing:
  # padrão certo → reescrita
  "Clique aqui":           "Toque aqui"   # mobile-first
  "Salvar":                "Salvar"       # consistente, não trocar pra "Confirmar"
  "Cancelar":              "Cancelar"
  "Tem certeza?":          "Confirma essa ação?"

inclusivity:
  gender_neutral: true       # "o usuário" → "quem usa" / "pessoas"
  avoid: ["normal", "louco", "cego", "surdo"]  # capacitismo
  use_instead:
    "lista negra":   "lista bloqueada"
    "white label":   "marca neutra"

# ─── CONTEXT DETECTION (o que revisar vs ignorar) ───
context_rules:
  # Só revisar texto que vai pro USUÁRIO. Ignorar:
  ignore:
    - "código" (variáveis, imports, types, interfaces, enums)
    - "comentário em código" (// e /* */)
    - "string em arquivo de teste" (*.test.*, *.spec.*)
    - "string em arquivo de config" (*.config.*, .env*)
    - "string em fixture/mock"
    - "constantes UPPER_SNAKE_CASE"
    - "strings de log estruturado" (logger.info, logger.error)
    - "schemas Zod/Yup (campos)"
    - "JSDoc/TSDoc tags"
    - "URLs (http://, https://, mailto:)"
    - "regex patterns"
  revisar_apenas:
    - "JSX text node visível"
    - "atributos: alt, title, aria-label, placeholder"
    - "props textuais: label, message, description, helpText"
    - "arquivos i18n (locales/*, messages/*)"
    - "templates de email"
    - "conteúdo de markdown público (docs/, README)"
    - "string em new Error('...')" SE for visível ao user
```

Se arquivo não existe, agente **cria template** na primeira execução com
defaults sensatos pro idioma detectado E **auto-popula** `protected_terms`
extraindo de:

- `package.json` (name, author, contributors)
- `README.md` (H1, termos repetidamente capitalizados)
- `.env.example` (`SERVICE_NAME`, `BRAND_NAME`, `APP_NAME`)
- Variáveis de ambiente (`NEXT_PUBLIC_BRAND`)
- Constantes nomeadas em `src/lib/brand.ts` ou `src/config/brand.ts`

## A.1. Engine de decisão (como o agente "pensa" antes de flagar)

Antes de qualquer revisão, o agente roda este pipeline por token suspeito:

```
Token detectado como "possível erro" pelo LanguageTool/Vale
   ↓
1. Está em protected_terms ou allowed_code_switching?
   SIM → IGNORA (não é erro, é marca/produto/role)
   NÃO ↓
2. Está em technical_terms?
   SIM → IGNORA (aceito em qualquer locale)
   NÃO ↓
3. Matches algum proper_nouns_detection rule?
   SIM → ADICIONA ao protected_terms automaticamente +
          flag pra revisão humana (low severity)
   NÃO ↓
4. Está em arquivo/contexto da lista context_rules.ignore?
   SIM → IGNORA (é código, não copy)
   NÃO ↓
5. Está em context_rules.revisar_apenas?
   NÃO → IGNORA (não é texto de UI)
   SIM ↓
6. AGORA SIM, revisa contra:
   - LanguageTool (gramática + ortografia)
   - Vale (estilo)
   - Glossary (consistência)
   - Forbidden words
   - alex (inclusividade)
   - Tom (se LLM ativado)
```

### Exemplos práticos da engine

| Texto detectado | Decisão | Por quê |
|---|---|---|
| `<h1>Salon Pro Dashboard</h1>` | ✅ aceito | "Salon Pro" em protected_terms, "Dashboard" em technical_terms |
| `<p>Configurar webhook do Stripe</p>` | ✅ aceito | code-switching permitido, "webhook" e "Stripe" protegidos |
| `<Button>Salvr</Button>` | ❌ CRIT — typo "Salvr" | Texto de UI, não está em allow-list, LanguageTool detecta |
| `const PIN_LENGTH = 6` | ✅ ignorado | Constante UPPER_SNAKE_CASE em código (context_rules.ignore) |
| `<input placeholder="ex: ana@email.com" />` | ✅ aceito | "ana@email.com" é exemplo, placeholder OK |
| `// TODO: revisar copy` | ✅ ignorado | Comentário em código |
| `throw new Error('User_invalid')` | ⚠ HIGH | Erro técnico que pode vazar pra UI (deve ser i18n key) |
| `<p>Welcome to your painel!</p>` | ❌ CRIT | Mistura ruim — "Welcome" sem ser code-switching aceito |
| `<MasterAdminBadge>MASTER</MasterAdminBadge>` | ✅ aceito | "MASTER" em protected_terms (role do produto) |
| `<p>Olá Maykonbts, bem-vindo!</p>` | ✅ aceito | "Maykonbts" auto-detectado como nome próprio |
| `<button>Deletar</button>` | ❌ HIGH | "deletar" em forbidden_words → use "Excluir" |

## A.2. Auto-população de protected_terms (na primeira execução)

```ts
// Em pseudo-código do agente
function autoPopulateProtectedTerms(): string[] {
  const terms = new Set<string>();

  // 1. package.json
  const pkg = JSON.parse(readFile('package.json'));
  if (pkg.name) terms.add(pkg.name);
  if (pkg.author?.name) terms.add(pkg.author.name);
  pkg.contributors?.forEach(c => terms.add(c.name));

  // 2. README.md H1 + termos repetidamente capitalizados
  const readme = readFile('README.md');
  const h1 = readme.match(/^#\s+(.+)$/m)?.[1];
  if (h1) terms.add(h1);
  const capWords = [...readme.matchAll(/\b([A-Z][a-zA-Z]+(?:\s+[A-Z][a-zA-Z]+)*)\b/g)]
    .map(m => m[1])
    .reduce((acc, w) => (acc[w] = (acc[w] || 0) + 1, acc), {});
  Object.entries(capWords).filter(([_, n]) => n >= 3).forEach(([w]) => terms.add(w));

  // 3. .env.example — variáveis BRAND_*, APP_*, SERVICE_*
  const env = readFile('.env.example');
  const brand = env.match(/^(BRAND_NAME|APP_NAME|SERVICE_NAME)=(.+)$/gm) || [];
  brand.forEach(line => terms.add(line.split('=')[1].trim().replace(/['"]/g, '')));

  // 4. Constants files
  ['src/lib/brand.ts', 'src/config/brand.ts', 'src/constants/brand.ts'].forEach(f => {
    if (exists(f)) {
      const code = readFile(f);
      [...code.matchAll(/(?:BRAND|APP|PRODUCT)_(?:NAME|TITLE)\s*=\s*['"]([^'"]+)['"]/g)]
        .forEach(m => terms.add(m[1]));
    }
  });

  // 5. Roles do role-hierarchy template
  const roles = ['MASTER', 'ADMIN', 'GERENCIAL', 'OPERACIONAL',
                 'RECEPTION', 'PROFESSIONAL', 'MANAGER', 'SELLER'];
  if (exists('src/auth') || exists('src/roles')) {
    roles.forEach(r => {
      if (grepHits(r) > 0) terms.add(r);
    });
  }

  return [...terms].sort();
}
```

Resultado dessa população é gravado em `.blindar/copy-style.yml` na seção
`protected_terms` na primeira execução, com comentário explicando que foi
auto-detectado e o operador pode editar.

## B. Stack de validação (em camadas)

### Camada 1: Ortografia + gramática automatizada

```bash
# LanguageTool (open source, suporta pt-BR + 30 idiomas)
docker run -d -p 8010:8010 erikvl87/languagetool

# Lint via API
curl -X POST http://localhost:8010/v2/check \
  -d "text=Aqui esta o texto pra revisar" \
  -d "language=pt-BR"
```

Lib alternativa: **`languagetool-rust`**, **`pyspellchecker`**, ou
**`hunspell`** com dicionário pt-BR.

### Camada 2: Prose lint (estilo e clareza)

**Vale** (vale.sh) — customizável, lê regras YAML:

```yaml
# .vale.ini
StylesPath = vale-styles
MinAlertLevel = suggestion
[*.md]
BasedOnStyles = Blindar, Microsoft, write-good

# vale-styles/Blindar/Glossario.yml
extends: substitution
message: "Use '%s' em vez de '%s' (glossário do projeto)"
ignorecase: true
swap:
  reserva: agendamento
  customer: cliente
  delete: excluir
```

Roda em CI: `vale **/*.md src/**/*.tsx locales/**/*.json`

### Camada 3: Consistência terminológica (glossário)

```bash
# Detecta uso de termo "proibido" em copy de UI ou i18n
node scripts/check-glossary.js .blindar/copy-style.yml locales/
```

Falha se: encontrou `reserva` em algum lugar quando o termo correto é `agendamento`.

### Camada 4: Tom (LLM-based, opcional mas recomendado)

Para tom complexo (formal/casual, calor humano), usar LLM call **uma vez**
por revisão, batch de textos:

```ts
// Para cada arquivo de copy modificado no PR:
const prompt = `
Você é revisor de copy. Tom alvo:
- formality: casual
- pronoun: você
- warmth: friendly
- reading_level: 8

Avalie os textos abaixo. Para cada um:
- score 1-5 (5 = no tom certo)
- sugestão de reescrita se score ≤ 3

Glossário obrigatório:
"agendamento" (não reserva/marcação)
"cliente" (não customer)

Texto: "${text}"
Retorne JSON: { score, suggestion }
`;
```

Cache resultados — só reavalia o que mudou no PR.

### Camada 5: Inclusividade

**alex.js** (`alextheword.com`) detecta:
- Capacitismo: "louco", "cego pra isso"
- Sexismo: "ele/dele" como genérico
- Termos coloniais: "blacklist/whitelist", "master/slave"
- Idadismo: "geração X", "ok boomer"

```bash
npx alex locales/**/*.json src/**/*.{tsx,jsx}
```

## C. Tipos de copy revisados (priorizado)

| Onde | Por quê crítico |
|---|---|
| **Botões primários** | "Salvar" típico mas projeto pode usar "Confirmar". Consistência total |
| **Mensagens de erro** | Frustração + medo. Devem ser claras + sem culpar user |
| **Mensagens de sucesso** | Confirmação que ação rolou. Não exagerar ("YAY!!!") |
| **Empty states** | Primeira impressão da feature. CTA claro |
| **Onboarding** | Define se user fica ou sai. Tom acolhedor |
| **Confirmações destrutivas** | "Tem certeza?" → o quê acontece se confirmar precisa estar **explícito** |
| **Emails transacionais** | Identificação + ação esperada. Anti-phishing |
| **Política de privacidade / TOS** | Legal — exige linguagem juridicamente correta |
| **Tooltips / labels** | Microcopy decide se feature é descoberta |
| **Notificações push** | < 60 chars, precisa convencer a abrir |
| **Placeholder de input** | Não substitui label (a11y). Exemplo, não instrução |

## D. Padrões obrigatórios por tipo

### Erro "amigável" (não técnico, não culpando user)

```
❌ "Erro fatal: AUTH_TOKEN_EXPIRED"
❌ "Você fez algo errado"
❌ "Permissão negada"
✅ "Sua sessão expirou. Faça login novamente."
✅ "Não conseguimos completar essa ação. Tente de novo em alguns segundos."
✅ "Você não tem acesso a essa página."
```

Estrutura: **o que aconteceu + o que fazer agora** (nunca só "erro").

### Empty state

```
Título:  Frase de 3-6 palavras
Texto:   1-2 frases explicando o porquê + benefício de preencher
CTA:     Verbo de ação ("Criar primeiro agendamento")
```

### Confirmação destrutiva

```
Título:  "Excluir [nome do item]?"
Texto:   "Essa ação não pode ser desfeita. [nome] e [N consequências]
         serão perdidos."
Botão 1: "Cancelar" (secondary)
Botão 2: "Sim, excluir" (danger — confirma o quê!)
```

NUNCA "OK / Cancelar" em destrutivo (user clica "OK" automático).

### Push notification

```
< 50 chars título: "João confirmou às 14h"  (não "Notificação")
< 100 chars corpo: "Atendimento Cabelo de cor agendado pra amanhã."
```

## E. Greps obrigatórios

```bash
# Erro técnico vazando pra UI (deveria ser amigável)
rg -n "(fatal|exception|stack trace|TypeError|undefined)" --type tsx --type jsx \
   -g 'src/**/*.tsx' -g '!**/test/**'

# Mensagens de erro hardcoded em código (deveriam vir do i18n)
rg -nU "throw new (Error|Exception)\(['\"][A-Za-zÀ-ú]{20,}" --type ts --type py

# Botão "Tem certeza?" sem contexto (vago)
rg -n "['\"]Tem certeza\\?['\"]" --type tsx --type jsx

# Confirmação só "OK" / "Cancelar" em destrutivo
rg -nB 5 "delete|remove|destrutiv" --type tsx -A 10 | rg "['\"]OK['\"]"

# Texto vazio onde deveria ter
rg -n "title=['\"]['\"]" --type tsx --type jsx
rg -n "placeholder=['\"]['\"]" --type tsx --type jsx
rg -n "<title></title>" --type tsx --type jsx --type html

# Concatenação de string que vira plural quebrado
rg -n "['\"][a-z]+\s*['\"]\s*\+\s*\w+\s*\+\s*['\"]\s*[a-z]+s\b" --type ts

# Maiúsculas inconsistentes (Title Case vs Sentence case misturado)
# (heurística: > 50% das chaves em locale têm Title Case mas > 20% Sentence)
node scripts/check-case-consistency.js locales/

# Tradução faltando (chave existe em pt mas não en)
diff <(jq -r 'keys[]' locales/pt-BR.json | sort) \
     <(jq -r 'keys[]' locales/en-US.json | sort)
```

## F. Workflow do agente em um round

```
1. Detecta arquivos modificados (git diff) com copy:
   - locales/*.json
   - src/**/*.tsx (texto JSX)
   - emails/**/*.html
   - docs legais

2. Para cada texto:
   a. LanguageTool → erros de gramática/ortografia
   b. Vale → estilo (passos clichês, voz passiva excessiva)
   c. Glossário → termos proibidos
   d. alex → inclusividade
   e. (opcional) LLM → score de tom

3. Severidade:
   - CRIT: ortografia em produção, erro técnico em UI, glossário violado, termo proibido
   - HIGH: tom inconsistente, plural quebrado, sem CTA em empty state
   - MED:  voz passiva excessiva, frases longas (>30 palavras)
   - LOW:  sugestão estilística

4. Output:
   - Patch sugerido pra cada finding crit/high
   - Round bloqueia merge se houver CRIT
   - Adiciona métrica em sec.html
```

## G. Output esperado em sec.html

```
┌─ Content Quality (Módulo 12) ────────────────────────────┐
│ Config de tom (.blindar/copy-style.yml) : ✅ criado       │
│ Idiomas suportados                       : pt-BR, en-US   │
│ Cobertura de chaves                       : 100%          │
│ Ortografia (LanguageTool)                 : 0 erros ✅    │
│ Gramática + concordância                  : 0 erros ✅    │
│ Glossário violado (termos errados)        : 0 ✅          │
│ Termos proibidos detectados               : 0 ✅          │
│ Inclusividade (alex.js)                   : 0 warnings ✅ |
│ Botões consistentes                       : ✅            │
│ Empty states com CTA claro                : 12/12 ✅      │
│ Erros técnicos vazando pra UI             : 0 ✅          │
│ Confirmação destrutiva com texto explícito: 8/8 ✅        │
│ Reading level médio (Flesch-Kincaid)      : 7.2 ✅ (alvo 8)│
│ Vale prose lint                           : 0 errors      │
│ Tom score (LLM, amostra)                  : 4.6/5 ✅      │
│ Status                                    : ✅ POLISHED   │
└───────────────────────────────────────────────────────────┘
```

## H. Anti-padrões (CRIT — bloqueia merge)

- ❌ Erro técnico vazando pra UI ("undefined is not a function" em produção)
- ❌ Ortografia errada em texto visível ao user
- ❌ Glossário misturado: "agendamento" e "reserva" no mesmo produto
- ❌ Confirmação destrutiva genérica ("Tem certeza?")
- ❌ "OK"/"Cancelar" em delete (deveria ser "Excluir"/"Cancelar")
- ❌ Mensagem de erro culpando o user ("você fez errado")
- ❌ Plural com concatenação (`count + " items"` — quebra em pt/ru/pl)
- ❌ Termo proibido pelo config (`forbidden_words`)
- ❌ Pronoun inconsistente (mistura "você" e "tu" no mesmo idioma)
- ❌ Botão "Salvar" virando "Confirmar" sem critério
- ❌ Push notification > 100 chars (cortado pelo SO)
- ❌ Placeholder substituindo label (a11y quebrada)
- ❌ TODOS OS BOTÕES EM MAIÚSCULAS (parece gritar)
- ❌ Termo discriminatório ("blacklist", "master/slave" — alex pega)
- ❌ Tradução literal de inglês ("clique aqui" em mobile)

## I. Anti-padrões médios (sugestão, não bloqueio)

- ⚠ Voz passiva excessiva (>30% das frases)
- ⚠ Frase com > 30 palavras
- ⚠ Mais de 1 ponto de exclamação por tela
- ⚠ Termo técnico sem explicação (em produto pra leigo)
- ⚠ Tooltip que repete o label (sem valor)

## J. Interação com outros agentes

- **config-externalization**: extrai textos hardcoded → este revisa qualidade do que está em i18n
- **i18n-tz**: garante chaves em todos os locales → este garante qualidade do conteúdo de cada locale
- **responsive-a11y**: garante labels nos inputs → este garante que o **conteúdo** do label é claro
- **onboarding-ux**: define empty states → este revisa o copy deles
- **email-deliverability**: garante DKIM/SPF/DMARC → este revisa qualidade do template de email
- **seo-marketing-meta**: gera title/description → este revisa se title é único e descritivo

## K. Para projeto multi-idioma

Cada locale tem revisor próprio:
- pt-BR: LanguageTool pt + dicionário Aurélio
- en-US: LanguageTool en-US + Vale + write-good
- es-ES: LanguageTool es + dicionário RAE

NÃO traduzir literal — adaptar ao idioma (idioms diferentes em cada região).

## L. Setup inicial (primeira execução em projeto novo)

```bash
# 1. Cria copy-style.yml com defaults
blindar init copy-style

# 2. Operador edita config (5-10 min):
#    - confirma idiomas
#    - revisa glossário sugerido (escolha de termos preferidos)
#    - lista forbidden_words específicos do produto

# 3. Roda LanguageTool localmente (Docker) ou usa API hosted
# 4. Configura Vale com regras Microsoft + Blindar
# 5. CI roda em cada PR que toca arquivo de copy
```
