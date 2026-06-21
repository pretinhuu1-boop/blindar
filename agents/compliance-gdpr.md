---
name: compliance-gdpr
category: compliance
module: 8
priority: P1
description: |
  GDPR (UE) — cobre 6 requisitos não-óbvios além do "consent banner":
  legal basis documentado por processamento, ROPA (Record of Processing
  Activities), DPIA pra alto risco, processadores em DPA, Transfer
  Impact Assessment pra dados saindo da UE, ePrivacy diretiva pra
  cookies. Mesmo se principal mercado é Brasil, qualquer usuário UE
  ativa o regime — multa até 4% do faturamento global.
---

# Agent: compliance-gdpr

## Missão

LGPD ≠ GDPR. Quem opera só no Brasil ainda precisa de GDPR se aceita
1 usuário UE. Multa máxima: 20M EUR ou 4% do faturamento global. Este
agente prescreve o mínimo pra estar em compliance.

## Quando rodar

- Módulo 8 selecionado
- Detectado: domínio com clientes UE, ou aceita signup sem geo-filtro
- Operador pediu "GDPR", "DSGVO", "Datenschutz", "Article 30"

## A. Legal basis por processamento

Cada uso de dado pessoal precisa de UMA das 6 bases:

1. **Consent** (explícito, opt-in, retirável)
2. **Contract** (necessário pra cumprir contrato com user)
3. **Legal obligation** (lei exige)
4. **Vital interests** (proteger vida)
5. **Public task** (autoridade pública)
6. **Legitimate interest** (precisa de LIA — balancing test)

Documentar **qual base** pra **qual processamento** em tabela:

```sql
CREATE TABLE processing_activities (
  id           UUID PRIMARY KEY,
  name         TEXT NOT NULL,             -- 'send marketing email'
  description  TEXT NOT NULL,
  data_categories TEXT[],                 -- ['email', 'name']
  data_subjects TEXT[],                   -- ['customers']
  purpose      TEXT NOT NULL,
  legal_basis  TEXT NOT NULL,             -- consent | contract | ...
  retention_days INTEGER NOT NULL,
  processors   TEXT[],                    -- ['Mailchimp', 'SendGrid']
  cross_border BOOLEAN DEFAULT false,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

## B. ROPA (Article 30)

Obrigatório se >250 employees ou processamento sistemático. Tabela acima
é o início. Inclui:

- Controller + DPO contato
- Categorias de dados
- Recipients (processors + sub-processors)
- Transfers (cross-border)
- Retention periods
- Security measures

Exportável em PDF a qualquer momento (autoridade pode pedir).

## C. DPIA (Data Protection Impact Assessment)

Obrigatório pra processamento de **alto risco**:
- Profiling automático com efeito legal
- Dados de menores em escala
- Dados sensíveis (saúde, biometria, raça)
- Vigilância sistemática

Template em `docs/compliance/dpia-template.md` com 11 seções
(Art. 35 GDPR).

## D. DPA (Data Processing Agreement) com processadores

Cada vendor que toca dado pessoal precisa ter DPA assinado.

Lista típica:
- Stripe (payment data)
- SendGrid/Resend (email)
- Sentry (error logs com PII?)
- PostHog (analytics)
- AWS/Vercel/Supabase (hosting)

Verifica em `docs/compliance/dpas/` — arquivo por vendor com PDF + data.

## E. TIA (Transfer Impact Assessment)

Pós-Schrems II (2020). Se dado vai pra fora da UE/EEA, precisa avaliar
**proteção real** no país destino (não só SCC).

EUA: complicado (FISA 702). Solução comum:
- Hosting na UE quando possível
- Encryption at rest com chaves na UE
- SCC + measures suplementares documentados

`docs/compliance/tia-aws.md`, `tia-vercel.md`, etc.

## F. Cookie banner (ePrivacy Directive, não GDPR)

GDPR sozinho NÃO regula cookies — é ePrivacy Directive. Mas ambos juntos
exigem:

- **Opt-in ANTES** de qualquer cookie não-essencial (analytics, marketing)
- "Continuar navegando = aceitar" = ILEGAL
- Botão "Rejeitar" tão visível quanto "Aceitar"
- Granular por categoria
- Mudar preferência em 1 clique a qualquer momento
- Log de consent com versão do banner

Lib: Cookiebot, OneTrust, Klaro, ou própria.

## G. Direitos do data subject (8 direitos)

| Art. | Direito | Tempo de resposta |
|---|---|---|
| 15 | Acesso (cópia dos dados) | 30 dias |
| 16 | Retificação | 30 dias |
| 17 | Apagamento ("right to be forgotten") | 30 dias |
| 18 | Restrição de processamento | 30 dias |
| 20 | Portabilidade (formato estruturado, JSON/CSV) | 30 dias |
| 21 | Oposição | imediato pra marketing |
| 22 | Não-sujeito a decisão automática | sempre |
| — | Retirar consent | tão fácil quanto dar |

UI obrigatório em `/privacy/my-data` com botões pra cada.

## H. Breach notification (Art. 33-34)

- **72h** pra notificar autoridade supervisora (vs LGPD: 3 dias úteis)
- Notificar data subjects se "alto risco"
- Documentar TODO breach em log interno (mesmo os não-notificados)

Runbook em `docs/runbooks/breach-notification-gdpr.md`.

## I. Dados de menores

- < 16 anos (alguns países: 13): precisa consent dos pais
- Verificação razoável (não só checkbox)
- Linguagem clara apropriada à idade

## J. Greps

```bash
# Cookie set antes de consent (CRIT)
rg -nU "setCookie|document\.cookie\s*=" --type ts -B 5 | rg -v "consent|essential"

# Cross-border transfer sem DPA
# (manual: verificar lista de vendors em package.json + DPAs em docs/)

# Endpoint sem rate limit (Art. 32 security)
# (coberto por network-security)

# Dados sensíveis sem extra protection
rg -n "(cpf|ssn|health|race|religion|biometric)" --type ts -A 3 | rg -v "encrypt"
```

## Output em sec.html

```
┌─ Compliance GDPR (Módulo 8) ─────────────────────────────┐
│ ROPA (Art. 30)                : ✅ 23 processing activities│
│ Legal basis documentado       : ✅ por activity           │
│ DPIA pra alto risco           : ✅ 2 DPIAs                │
│ DPAs com processadores        : ✅ 8/8 vendors            │
│ TIA pra transferência fora UE : ✅ AWS US + Vercel        │
│ Cookie banner com opt-in real : ✅ Klaro                  │
│ "Rejeitar" tão visível como "Aceitar": ✅                 │
│ 8 direitos implementados      : ✅ /privacy/my-data       │
│ DSAR fulfillment time         : 4 dias média (meta < 30)  │
│ Breach notification runbook   : ✅ 72h target             │
│ Gate Art. 8 (menores)         : ✅ idade ≥ 16             │
│ DPO contato público           : ✅ dpo@example.com        │
│ Status                        : ✅ COMPLIANT GDPR        │
└───────────────────────────────────────────────────────────┘
```

## Anti-padrões

- ❌ "Continuar navegando = aceitar cookies"
- ❌ Botão "Rejeitar" escondido em modal de 3 cliques
- ❌ Cookie analytics sem consent
- ❌ Marketing pra UE sem opt-in explícito
- ❌ Vendor processando PII sem DPA assinado
- ❌ Transfer pra EUA sem SCC + TIA
- ❌ Right to be forgotten = "marcar deleted_at" (não apaga em backup)
- ❌ Sem DPO designado em empresa que precisa (>250 emp, alto risco)
- ❌ Banner que pede consent toda vez (não persiste decisão)
- ❌ "Aceitar tudo" pré-marcado
