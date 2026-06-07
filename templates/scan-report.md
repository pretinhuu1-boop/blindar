# Strategic Scan Report — {project_name}

> Gerado por `blindar` v{version} em {timestamp}
> Esta é a saída da **Fase 0 (Strategic Scan & Planning)**.

---

## Sumário

- **Projeto**: {project_name}
- **Stack detectada**: {stack}
- **Arquivos varridos**: {files_scanned} (de {files_total})
- **Findings**: {total} ({crit} crit, {high} high, {med} med, {info} info)
- **Tempo estimado de execução**: {estimated_time_min} min ({estimated_rounds} rounds)
- **Paralelismo recomendado**: {max_parallel} agentes simultâneos

---

## Findings (ordem por severidade)

### 🔴 CRÍTICAS — fortemente recomendado aplicar

#### [1] Categoria 4 (Secrets) · crit · Esforço: Sm

- **Encontrado**: `.env` commitado em `git log` (commit `abc123` por example@email.com em 2025-12-15)
- **Sugerido**: Remover do histórico via `git filter-repo`, rotacionar todas as chaves expostas, adicionar `.env*` ao `.gitignore`
- **Agente**: `agents/runtime-secrets.md` + `agents/supply-chain.md`
- **Ver também**: ISO 27001 A.5.10, NIST CSF PR.DS-1

#### [2] Categoria 1 (Autenticação) · crit · Esforço: Md

- **Encontrado**: Senhas armazenadas como `sha1(password)` em `users.password_hash`
- **Sugerido**: Migrar pra Argon2id (preferido) ou bcrypt cost≥12. Re-hash gradual em login.
- **Agente**: `agents/cryptography.md`
- **Ver também**: OWASP ASVS V2.4

#### [3] Categoria 3 (Storage) · crit · Esforço: XL

- **Encontrado**: Arquivo `data.json` lido/escrito em todas as operações (JSON-as-DB)
- **Sugerido**: Migrar pra SQLite (mínimo) ou PostgreSQL. Schema versionado, migrations, índices em `user_id`, `email`.
- **Agente**: refactor sugerido — fora do escopo padrão, abre PR de discussão
- **Atenção**: maior esforço do scan. Pode adiar pra ciclo separado.

---

### 🟠 ALTAS — forte recomendação

#### [4] Categoria 1 (Autenticação) · high · Esforço: Sm

- **Encontrado**: `/login` endpoint sem rate-limit
- **Sugerido**: Adicionar rate-limit (5 tentativas / 15 min / IP+email) + lockout exponencial
- **Agente**: `agents/access-control.md` + `agents/network-security.md`

#### [5] Categoria 1 (Autenticação) · high · Esforço: Md

- **Encontrado**: Sem MFA disponível
- **Sugerido**: Adicionar TOTP (RFC 6238) opcional ou obrigatório pra admin
- **Agente**: `agents/access-control.md`

#### [6] Categoria 6 (API) · high · Esforço: Sm

- **Encontrado**: `CORS: *` com `credentials: true`
- **Sugerido**: Lista explícita de origens permitidas
- **Agente**: `agents/network-security.md`

---

### 🟡 MÉDIAS — recomendado

#### [10] Categoria 5 (Frontend) · med · Esforço: Sm

- **Encontrado**: Sem `Content-Security-Policy` header
- **Sugerido**: CSP report-only primeiro, enforce em 2 semanas
- **Agente**: `agents/frontend.md`

#### [11] Categoria 5 (Frontend) · med · Esforço: Md

- **Encontrado**: `innerHTML` usado em 8 locais sem sanitization
- **Sugerido**: DOMPurify ou textContent. Trusted Types se possível.
- **Agente**: `agents/frontend.md`

---

### ℹ️ INFO — otimizações

#### [16] Categoria 9 (Logging) · info · Esforço: Sm

- **Encontrado**: Logs em texto livre (`console.log("user logged in:", email)`)
- **Sugerido**: Logger estruturado (pino/winston/structlog) + correlation ID + redaction de PII
- **Agente**: `agents/observability.md`

#### [17] Categoria 14 (Observability) · info · Esforço: Sm

- **Encontrado**: Sem health endpoints
- **Sugerido**: `/health/live` (proc respira) + `/health/ready` (deps OK) + `/health/deep` (full check)
- **Agente**: `agents/observability.md`

#### [18] Categoria 9 (Logging) · info · Esforço: Md

- **Encontrado**: Sem audit chain
- **Sugerido**: Append-only audit + Merkle hash chain pra mudanças em PII
- **Agente**: `agents/compliance.md`

---

## 🤖 Plano de execução

### Hardware detectado

```
OS:        {os}
CPU cores: {cpu_cores} (logical)
RAM:       {ram_gb} GB
Storage:   {storage} disponível
```

### Estratégia de paralelismo

```
Max agents simultaneous:  {max_parallel}
Discovery (Phase 2):       3 agentes paralelos    (~3 min)
Rounds (Phase 4):          {parallel_rounds} rounds paralelos    (~{round_min} min cada)
Adversarial (Phase 5):     4 lentes + verify       (~10 min)
```

### Grupos de agentes independentes (paralelizáveis)

```
Grupo A (alto throughput):
  - access-control
  - cryptography
  - observability

Grupo B (médio throughput):
  - frontend
  - network-security
  - supply-chain

Grupo C (sequencial obrigatório):
  - resilience (depende de observability)
  - business-logic (depende de access-control + DB)
```

### Tempo total estimado

- **Cenário otimista** (CI rápida, sem adversarial dispara round): ~{optimistic_h}h
- **Cenário realista** (CI ~5min, 1 adversarial round): ~{realistic_h}h
- **Cenário conservador** (CI ~10min, 2 adversarial rounds): ~{conservative_h}h

---

## 🎯 Seleção interativa

```
Quais findings aplicar? Responda:

  • Números separados por vírgula: "1,2,4,7,10"
  • Range: "1-3,10-12,16"
  • "all" pra tudo (18 findings)
  • "crit" pra só críticas (1-3)
  • "crit+high" pra críticas e altas (1-6)
  • "crit+high+med" (1-15)
  • "none" pra cancelar e sair

→ _
```

---

## ⚠ Notas sobre estimates

- Tempo estimado é heurística. CI lenta multiplica por 2-3x.
- Esforço **XL** (#3 storage migration) pode quebrar funcionalidade —
  considerar fora deste ciclo.
- Findings **info** não bloqueiam release. Aplique se sobrar tempo.
- `crit` que envolve breaking change (#2 re-hashing senhas) tem migração
  gradual planejada pelo agente — usuários não são deslogados em massa.

---

## Próximo passo

Operador responde a seleção → skill cria `.blindar/plan.json` →
Fase 1 (Baseline) inicia.

Se `none`: skill sai limpo, sem modificações.

---

*Report gerado por `agents/strategic-scanner.md` da `blindar` v{version}.*
*Schema: `schemas/findings.schema.json` + nova `plan.schema.json`.*
