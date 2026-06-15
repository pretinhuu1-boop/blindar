---
name: compliance-hipaa
category: compliance
module: 8
priority: P2
description: |
  HIPAA (saúde US): Privacy Rule, Security Rule (administrative,
  physical, technical safeguards), Breach Notification Rule (60 dias),
  BAA com vendors, audit logs 6 anos, encryption at-rest + in-transit,
  minimum necessary principle, patient access right (45 dias). Multa
  até $2M+ por violação categórica.
---

# Agent: compliance-hipaa

## Missão

Qualquer app de saúde nos EUA com PHI (Protected Health Information).
HIPAA é regime federal + estados. Multa categoria 4 (willful neglect):
até US$2M+ por violação. Este agente cobre o mínimo.

## Quando rodar

- Módulo 8 selecionado
- Projeto manuseia PHI: prontuário, exame, prescrição, agendamento médico
- Mercado: EUA ou comércio com USA

## A. O que conta como PHI

18 identifiers (Safe Harbor list):
1. Nome
2. Endereço (mais específico que estado)
3. Datas (nascimento, admissão, alta — exceto ano se >89)
4. Telefone, fax, email
5. SSN, MRN (medical record), health plan, account, license
6. VIN, license plate
7. Device serial number
8. URL, IP
9. Biometric (fingerprint, voice)
10. Photo
11-18. ...

PHI = info de saúde + identifier. Anonymized data ≠ PHI.

## B. Privacy Rule — Minimum Necessary

Acessar SÓ o mínimo necessário pro propósito. Implementação:

- Role-based access (`role-hierarchy`): médico vê seus pacientes, recepção vê agenda, NÃO histórico clínico
- Audit log a cada acesso
- Justify access (UI pede motivo em acesso fora do padrão)

## C. Security Rule — 3 categorias

### Administrative safeguards
- Security Officer designado (nome documentado)
- Workforce training anual obrigatório
- Sanction policy (consequências de violação)
- Access management procedure
- Risk analysis anual

### Physical safeguards
- Facility access controls (data center, escritório)
- Workstation security (lock screen, full disk encrypt)
- Device disposal (wipe antes de descarte)
- Media controls (USB tracking)

### Technical safeguards
- Access controls (unique user IDs, automatic logoff, encryption)
- Audit controls (logs de tudo)
- Integrity (PHI não alterada sem autorização — hash)
- Transmission security (TLS 1.2+)

## D. Encryption (mandatory mas implicit — `addressable`)

- At-rest: AES-256, chaves em KMS (não em código)
- In-transit: TLS 1.2 minimum, 1.3 preferred
- Backup também cifrado

## E. BAA (Business Associate Agreement)

Vendor que processa PHI assina BAA. Inclui:

- AWS (HIPAA-eligible services list)
- Google Cloud (BAA pra Workspace + GCP)
- Microsoft Azure
- Stripe (não healthcare claims)
- Twilio (Signed BAA disponível)
- SendGrid (com BAA)

Vendors sem BAA NÃO podem tocar PHI. Verificar lista de processadores.

## F. Audit log obrigatório (6 anos retenção)

```sql
CREATE TABLE phi_access_log (
  id           UUID PRIMARY KEY,
  actor_id     UUID NOT NULL,
  patient_id   UUID NOT NULL,
  action       TEXT NOT NULL,        -- 'view', 'modify', 'export', 'print'
  resource_type TEXT NOT NULL,        -- 'chart', 'medication', 'image'
  resource_id  UUID,
  justification TEXT,                 -- "treating patient" / etc
  ip           INET,
  user_agent   TEXT,
  at           TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

Retenção 6 anos. Em frio storage após 1 ano.

## G. Patient access right (45 dias)

Patient pode pedir:
- Cópia dos próprios records
- Correção de erros
- Histórico de divulgações

Implementar em `/patient/my-records`. Resposta < 30 dias (45 com extensão).

## H. Breach notification (60 dias)

- Notificar HHS Secretary
- Notificar paciente
- > 500 affected: media notification + HHS publishes em "wall of shame"

Runbook em `docs/runbooks/hipaa-breach.md`.

## I. Telehealth specifics

- Plataforma com HIPAA-compliant video (Daily.co, Twilio Programmable Video, Zoom Healthcare)
- NÃO usar Zoom regular, FaceTime, WhatsApp pra consulta
- Consentimento documentado pra telehealth

## J. De-identification (pra research)

Safe Harbor: remover 18 identifiers. Expert Determination: estatístico
prova baixo risco re-identification.

## K. Greps

```bash
# PHI em log (CRIT)
rg -n "logger\\.(info|debug|warn|error)" --type ts -A 3 | rg -i "(diagnosis|prescription|patient_name|mrn|ssn)"

# Vendor sem BAA listado
# (verificar manualmente lista de vendors vs BAAs)

# Acesso a PHI sem audit
rg -n "(patient|medical|chart)\\.find" --type ts -A 5 | rg -v "audit"

# Encryption não-validado
rg -n "AES|encryption" --type ts | rg -v "KMS|key_management"
```

## Output em sec.html

```
┌─ Compliance HIPAA (Módulo 8) ────────────────────────────┐
│ Security Officer designado    : ✅ documentado            │
│ Risk analysis anual           : ✅ 2026                  │
│ Workforce training (12 meses) : ✅ 100% staff            │
│ BAAs assinados                : 7/7 vendors PHI          │
│ Encryption at-rest (AES-256)  : ✅ KMS                   │
│ TLS 1.2+ in-transit           : ✅                       │
│ Audit log PHI access          : ✅ 6 anos retenção        │
│ Minimum necessary (RBAC)      : ✅                       │
│ Patient access UI             : ✅ /patient/my-records   │
│ Breach notification runbook   : ✅ 60 dias               │
│ Telehealth platform           : Daily.co (BAA signed)   │
│ Status                        : ✅ HIPAA-COMPLIANT      │
└───────────────────────────────────────────────────────────┘
```

## Anti-padrões

- ❌ PHI em log estruturado (mesmo "redacted" se grep mostrar)
- ❌ Vendor sem BAA (CRIT — violation)
- ❌ Zoom regular pra telehealth (sem BAA)
- ❌ Email PHI sem encryption (Gmail regular)
- ❌ Audit log < 6 anos retenção
- ❌ Patient access ignorado/demorado (>45 dias)
- ❌ Backup não-cifrado
- ❌ Acesso PHI sem audit por user/timestamp/resource
- ❌ Anonymization fraca (só remove nome — outros 17 identifiers vazam)
- ❌ Não documentar Security Officer
- ❌ Risk analysis "ano passado" sem update
- ❌ Sem sanction policy
