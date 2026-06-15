---
name: runtime-secrets
category: security
module: 2
priority: P0
description: |
  Secrets em runtime: nunca em log (greps em logger.info/error), nunca em memória além do necessário, redaction automático em error.stack, env vars carregadas via dotenv-safe, rotação programada.
---

# Agent: runtime-secrets

Caça secrets em **runtime** (memória, env, logs, processos). Complementa
[`cryptography.md`](cryptography.md) (storage) e
[`supply-chain.md`](supply-chain.md) (git history).

⚠ **Status v0.6.0**: novo agente. Padrões consolidados, ferramental
inclui open-source maduro (memlabs, /proc, env audit). Refinamentos
conforme uso real.

## Quando ativar

Round que envolva ambientes onde secrets podem **vazar em tempo de
execução** mesmo que código esteja "limpo":

- Processo lê env var e loga
- Heap dump com tokens de sessão
- Log de erro com URL completa (`https://api?token=abc`)
- Core dump em produção
- Debugger conectado em prod

## Padrões cobertos

### 1. Env var leakage

- `print(os.environ)` em código de debug que escapou pra prod
- Health endpoint retorna `process.env` (visto: dezenas de bug bounties)
- Error page exibe stack trace com env contexto

**Mitigação**:
- **Allowlist de env vars que podem ser logadas** (não denylist —
  default deny)
- **Sanitizer no formatter de log** — regex `SECRET|TOKEN|KEY|PASSWORD`
  + valor `>20 chars` → `***`
- **Health endpoint** retorna apenas status, não env

### 2. Token em URL (Referer leakage)

- Token em query string (`?token=abc`) viaja em Referer pra terceiros
- Token em path (`/api/token/abc/resource`) idem
- Token em fragment é melhor (não viaja em request) mas ainda vaza
  em history/logs

**Mitigação**: Tokens em **Authorization header** ou **POST body**.
Nunca em URL.

### 3. Heap/memory dump

- Core dump em prod com strings de senhas/tokens
- Logs de OOM-kill com snapshot de memória
- `pickle.dumps(session)` pra debug que vai pra log

**Mitigação**:
- `ulimit -c 0` em prod (desabilita core dump)
- Secrets em estrutura zeroizável (`bytearray` + zero após uso)
- Não fazer dump de objeto-sessão em log

### 4. Process listing

- `/proc/<pid>/environ` legível por outros usuários
- `ps aux` mostra args incluindo flags com tokens
- Container compartilhado mostra env de outros tenants

**Mitigação**:
- Boot com env, **delete env vars imediatamente** após carregar pra config
  in-process
- Secrets via stdin/file, não argv
- Container isolation (não rodar como root, não compartilhar PID namespace)

### 5. Debugger / introspection em prod

- `/debug/pprof` (Go) habilitado em prod
- Django Debug Toolbar exposto
- Rails Web Console
- Node `--inspect` em porta exposta

**Mitigação**: **Grep estático que falha** se essas flags aparecem em
config de produção. Boot guard que aborta se debugger detectado.

### 6. Backup / dump de DB contém secret

- `pg_dump` de tabela `users` com `password_hash` (OK se Argon2id; FAIL se
  reversível) ou `api_keys` em texto
- Snapshot de Redis com sessões ativas

**Mitigação**: Sanitização pré-backup (REPLACE em campos sensíveis pra
backup público) OU criptografia at-rest do backup com chave separada
(ver [`cryptography.md`](cryptography.md)).

### 7. Crash report / telemetry

- Sentry/Rollbar/Bugsnag captura request com Authorization header
- Frontend errors enviam state com tokens
- LLM logs enviados ao provider incluem secrets do prompt

**Mitigação**:
- **Scrubber configurado** no SDK do error tracker (lista de chaves a
  redagir)
- Frontend: filtrar Redux/state antes de enviar
- LLM: NUNCA mandar secrets pra modelo terceiro

## Prompt

```
Audit runtime secret leakage:

1. Buscar prints/logs de env (grep por os.environ, process.env, dotenv keys)
2. Endpoints que retornam config (health, debug, status) — auditar payload
3. Tokens em URL query/path em qualquer endpoint
4. Core dumps habilitados? ulimit em entrypoint?
5. Debugger flags em config de prod (pprof, Django toolbar, Rails console)
6. Backup process sanitiza ou cifra?
7. Sentry/Bugsnag config tem scrubber? Frontend filtra state?

Implement (≤80 LOC):
1. Sanitizer central de log (allowlist de campos publicáveis)
2. Boot guard que aborta se env tem chave proibida em prod (debug=true, etc.)
3. Helper de redaction reutilizado em error pages
4. Grep estático que falha se debugger flag aparecer em prod config
5. Test: fixture com token tenta vazar em log/error → DEVE ser redacted
6. sec.html: categoria runtime_secrets, ATKs por vazamento detectado
```

## Princípios não-negociáveis

- **Default deny no logging**: campo só vai pra log se explicitamente
  marcado seguro. Sem allowlist = sem log.
- **Token em Authorization header, jamais URL**
- **Core dump desabilitado em prod** (`ulimit -c 0`)
- **Debugger flags têm grep estático bloqueante**
- **Scrubber em error tracker** com lista versionada

## Teste obrigatório

- Happy: log de operação normal não tem secret
- Edge: erro com Authorization header → header redacted
- Attack: tentativa de injetar secret em campo "público" (display_name
  com token) → log redacted

## Mapeamento de frameworks

| Framework | Controle |
|---|---|
| OWASP ASVS | V7 (Error handling & logging), V8 (Data protection) |
| ISO 27001 | A.8.12 (Data leakage prevention) |
| NIST CSF | PR.DS-1, PR.DS-5 |
| PCI-DSS | Req 3.3, Req 3.4 (PAN masking) |
| SOC 2 | CC6.1 |

## Limitações honestas

- **Não pega secrets que vazam por bug zero-day** em SDK terceiro
- **Não substitui rotação periódica** de credenciais (essa fica em
  [`cryptography.md`](cryptography.md) e runbook)
- **Memory forensics avançado** (heap walk de processos rodando) fica
  fora do escopo — vira ferramenta de IR
