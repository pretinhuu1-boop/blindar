---
name: healthtech-fhir
category: vertical
module: 8
priority: P0
description: |
  Healthtech BR/global com padrões FHIR R4/R5, HL7 v2, prontuário
  eletrônico (PEP/EHR), CFM 1821/2299 (telemedicina), LGPD art. 11
  (dados sensíveis de saúde). SMART on FHIR + OAuth 2.0 com PKCE,
  scopes granulares (`patient/*.read`, `user/*.*`), audit via
  Provenance, consentimento via Consent resource. Falha aqui é
  responsabilidade civil + sanção CFM + multa LGPD (até 2% faturamento).
---

# Agent: healthtech-fhir

## Missão

Qualquer app que toque prontuário, exame, receita, agendamento médico,
telemedicina ou pesquisa clínica. Healthtech BR opera sob LGPD art. 11
(dado sensível), Resolução CFM 1821/2018 (PEP), CFM 2299/2021
(telemedicina) e — se interoperar — padrões FHIR R4/R5 + HL7 v2.

PHI (Patient Health Info) vazado = dano moral + sanção ANPD + cassação
do médico responsável técnico. Tolerância zero.

## Quando rodar

- Módulo 8 selecionado
- Projeto declara stack FHIR (`@medplum/core`, `fhir.js`, `fhir-kit-client`, `smart-on-fhir`, `hapi-fhir`)
- Manuseio de prontuário, exame, prescrição, telemedicina
- Integração HIS/RIS/PACS/laboratório

Pula silencioso se zero indício de FHIR/healthtech no código.

## A. FHIR R4/R5 — resources core

| Resource | Uso | Campos obrigatórios |
|---|---|---|
| `Patient` | Cadastro paciente | `identifier` (CPF/CNS), `name`, `birthDate`, `gender` |
| `Practitioner` | Médico/enfermeiro | `identifier` (CRM/COREN), `name`, `qualification` |
| `Encounter` | Consulta/internação | `status`, `class`, `subject`, `period` (com timezone) |
| `Observation` | Sinal vital, exame | `status`, `code` (LOINC), `subject`, `effectiveDateTime`, `value*` |
| `Condition` | Diagnóstico | `code` (CID-10/SNOMED), `subject`, `clinicalStatus` |
| `Medication` | Prescrição | `code` (ATC/RxNorm), `dosage`, `route` |
| `AllergyIntolerance` | Alergia | `code`, `criticality`, `patient` |
| `DiagnosticReport` | Laudo | `status`, `code`, `subject`, `result[]`, **versioning obrigatório** |
| `Consent` | Consentimento | `status`, `scope`, `category`, `patient`, `provision` |
| `Provenance` | Audit trail | `target`, `recorded`, `agent`, `entity` |

**Patient.identifier** é o âncora. Sem ele, paciente não é rastreável
inter-sistemas. Use CPF + CNS (cartão SUS) com `system` apropriado:
```json
{ "system": "http://www.saude.gov.br/fhir/r4/NamingSystem/cpf", "value": "12345678900" }
{ "system": "http://www.saude.gov.br/fhir/r4/NamingSystem/cns", "value": "898001153559712" }
```

## B. SMART on FHIR — auth

OAuth 2.0 + PKCE (não implicit). Scopes granulares:

- `patient/*.read` — leitura de TODOS recursos do paciente logado
- `patient/Observation.read` — leitura SÓ de Observations
- `user/*.*` — acesso de profissional (broader)
- `system/*.read` — backend-to-backend (CDS Hooks, bulk export)
- `launch/patient` — contexto de paciente passado via launch
- `offline_access` — refresh token

Endpoints obrigatórios em `.well-known/smart-configuration`:
```
authorization_endpoint
token_endpoint
capabilities: [launch-ehr, client-public, sso-openid-connect]
```

**Toda chamada FHIR PRECISA validar scope** antes de retornar resource.
Não confie no client.

## C. CFM 1821/2018 — Prontuário Eletrônico

NGS2 (Nível de Garantia de Segurança 2) exigido:

- Assinatura digital ICP-Brasil em laudos
- Carimbo do tempo confiável
- Trilha de auditoria com hash em cadeia (blockchain leve OK)
- Retenção 20 anos (prontuário) / permanente (paciente falecido)
- Backup geograficamente distribuído

Documente certificação SBIS-CFM em `docs/compliance/sbis-ngs2.md`.

## D. CFM 2299/2021 — Telemedicina

Toda teleconsulta DEVE registrar:

1. **Médico**: CRM + UF (validar contra portal CFM)
2. **Paciente**: identidade verificada (foto documento, biometria)
3. **Data/hora**: com timezone (`America/Sao_Paulo`) + carimbo confiável
4. **Consentimento informado**: gravado (vídeo OU texto assinado digital)
5. **Modalidade**: teleconsulta, telediagnóstico, telecirurgia, etc.
6. **Prescrição**: assinada digital ICP-Brasil quando emitida
7. **Encaminhamento presencial**: registrado se houver

Plataforma sem essas garantias = exercício irregular da medicina.

## E. LGPD art. 11 — dado sensível de saúde

Bases legais admissíveis (NÃO use "legítimo interesse"):

- Consentimento específico e destacado (art. 11, I)
- Tutela da saúde por profissional/serviço/autoridade (art. 11, II.f)
- Estudos por órgão de pesquisa (art. 11, II.c) — com anonimização

DPIA (RIPD) obrigatório. Comunicação ANPD em 2 dias úteis em
incidente. Banco de dados em território nacional (preferível) ou com
SCC + adequação se internacional.

## F. PHI em log/console = vazamento

PHI tudo que combine identidade + dado clínico:

- Nome + diagnóstico (CID)
- CPF + medicação
- Foto + condição
- Endereço + exame
- MRN (Medical Record Number) puro

NUNCA logar. Use IDs opacos (UUID v4) em log + lookup separado
auditado.

## G. Consent resource — fluxo de compartilhamento

Antes de enviar PHI a 3º (operadora, lab, outro médico):

```json
{
  "resourceType": "Consent",
  "status": "active",
  "scope": { "coding": [{ "system": "...", "code": "patient-privacy" }] },
  "category": [{ "coding": [{ "code": "INFAO" }] }],
  "patient": { "reference": "Patient/123" },
  "dateTime": "2026-06-21T10:00:00-03:00",
  "performer": [{ "reference": "Patient/123" }],
  "provision": {
    "type": "permit",
    "period": { "start": "2026-06-21", "end": "2027-06-21" },
    "actor": [{ "reference": "Organization/lab-xyz" }],
    "action": [{ "coding": [{ "code": "access" }] }]
  }
}
```

Sem Consent ativo → 403 + log de tentativa.

## H. Provenance — audit obrigatório em mudança de prontuário

Toda mutação em `Patient`, `Condition`, `Observation`,
`MedicationRequest`, `DiagnosticReport` gera Provenance:

```json
{
  "resourceType": "Provenance",
  "target": [{ "reference": "Observation/abc" }],
  "recorded": "2026-06-21T10:00:00-03:00",
  "agent": [{
    "type": { "coding": [{ "code": "author" }] },
    "who": { "reference": "Practitioner/crm-12345-sp" }
  }],
  "entity": [{ "role": "revision", "what": { "reference": "Observation/abc/_history/1" } }]
}
```

DiagnosticReport.result alterado SEM Provenance + sem versioning = laudo
adulterado. Crime.

## I. Greps

```bash
# PHI em log (CRIT)
rg -n "(console\\.(log|error)|logger\\.(info|debug|warn|error))" --type ts -A 3 \
  | rg -i "(diagnosis|cid|prescription|patient_name|cpf|cns|mrn|prontuario)"

# Endpoint FHIR sem auth middleware
rg -n "(app|router)\\.(get|post|put|delete)\\(['\"]/(fhir|api/fhir)" --type ts -A 5 \
  | rg -v "(authenticate|requireAuth|verifyToken|smartAuth|scope)"

# Patient sem identifier
rg -n "resourceType.*Patient" --type ts --type json -A 10 \
  | rg -v "identifier"

# Telemedicina sem consentimento gravado
rg -n "(telemedicina|teleconsulta|telehealth)" --type ts -A 10 \
  | rg -v "(consent|consentimento|recording|gravacao)"
```

## J. Output em sec.html

```
┌─ Healthtech FHIR (Módulo 8) ─────────────────────────────┐
│ FHIR R4/R5 stack                  : ✅ @medplum/core     │
│ Patient.identifier (CPF/CNS)      : ✅ NamingSystem BR   │
│ SMART on FHIR + PKCE              : ✅                   │
│ Scope check em todas rotas FHIR   : ✅ 47/47             │
│ Consent resource em share         : ✅                   │
│ Provenance em mutações            : ✅ trail completa    │
│ DiagnosticReport versioning       : ✅ _history          │
│ CFM 1821 NGS2 (PEP)               : ✅ ICP-Brasil        │
│ CFM 2299 telemedicina             : ✅ registro completo │
│ LGPD art. 11 base legal           : ✅ consentimento     │
│ PHI em log                        : ✅ 0 ocorrências     │
│ Status                            : ✅ HEALTHTECH-READY │
└───────────────────────────────────────────────────────────┘
```

## Anti-padrões

- ❌ Patient sem identifier (paciente fantasma — sanção CFM)
- ❌ Endpoint `/fhir/*` sem scope check (CRIT)
- ❌ PHI em `console.log` ou log estruturado (LGPD art. 11)
- ❌ Compartilhar PHI sem Consent ativo (multa ANPD)
- ❌ Alterar DiagnosticReport sem versioning (`_history`)
- ❌ Mutar Observation sem gerar Provenance
- ❌ Telemedicina sem gravar consentimento + dados CFM
- ❌ Assinar laudo sem ICP-Brasil (CFM 1821)
- ❌ Encounter.period sem timezone (`America/Sao_Paulo`)
- ❌ OAuth implicit em vez de PKCE
- ❌ Scope `*/*.*` default (princípio do menor privilégio)
- ❌ Backup FHIR sem criptografia at-rest
- ❌ Retenção < 20 anos (CFM)
- ❌ Vendor sem cláusula LGPD art. 39 (operador)
