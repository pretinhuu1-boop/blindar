---
name: compliance-lgpd-br
category: compliance
module: 8
priority: P0
description: |
  LGPD/ANPD (Brasil). Consent gates, 6 endpoints Art. 18 (acesso/correção/exclusão/portabilidade/anonimização/oposição), runbook ANPD 72h, cookie banner real (opt-in), gate Art. 14 (menores), DPO designado.
---

# Agent: compliance-lgpd-br

Estende [`compliance.md`](compliance.md) com obrigações específicas da LGPD
e regulação da ANPD.

## Quando ativar

Discovery (Fase 1) detectou projeto BR. Sinais:

- Campos `CPF`, `CEP`, `RG`
- Idioma PT-BR no UI
- `.env` com `BRAZIL=true` ou `LOCALE=pt-BR`
- Deploy em região BR

Quando detectado, spawn este agente **adicionalmente** ao `compliance.md`.

## DOCS obrigatórios em `docs/lgpd/`

1. **`base-legal.md`** — qual base do Art. 7º (consentimento / legítimo
   interesse / execução de contrato / etc.) para CADA tratamento. Tabela
   por feature.
2. **`encarregado.md`** — DPO nome + contato + canal (Art. 41). Visível na
   política de privacidade.
3. **`ripd-{feature}.md`** — Relatório de Impacto à Proteção de Dados para
   tratamentos de alto risco (perfilamento, decisão automatizada, dados
   sensíveis). Template ANPD.
4. **`incidente-anpd.md`** — runbook 72h: detecção → contenção →
   notificação ANPD (formato + canal) → comunicação titular (Art. 48).
5. **`transferencia.md`** — se houver dados saindo do BR, base legal +
   cláusulas-padrão equivalentes a SCCs (Art. 33).
6. **`politica-privacidade.md`** — texto público, linkada no app/site,
   versionada.
7. **`termo-uso.md`** — versionado, exigindo aceite explícito.

## CÓDIGO — endpoints obrigatórios (Art. 18)

Cada titular pode exercer 6 direitos. Cada um vira endpoint autenticado +
rate-limit (DSAR DoS protection):

| Método | Endpoint | Direito |
|---|---|---|
| GET | `/api/lgpd/me` | Confirmação de tratamento (Art. 18 I) |
| GET | `/api/lgpd/export` | Acesso aos dados (Art. 18 II) |
| POST | `/api/lgpd/rectify` | Correção (Art. 18 III) |
| POST | `/api/lgpd/anonymize` | Anonimização/bloqueio (Art. 18 IV) |
| POST | `/api/lgpd/delete` | Eliminação (Art. 18 VI) |
| POST | `/api/lgpd/portability` | Portabilidade (Art. 18 V) |
| POST | `/api/lgpd/consent/revoke` | Revogação consentimento (Art. 18 IX) |

## CÓDIGO — gates obrigatórios

- **Consentimento**: granular por finalidade + revogável + auditado em chain.
- **Crianças/adolescentes (Art. 14)**: cadastro com data de nascimento,
  gate que exige consentimento parental para <18; bloqueia <13 sem revisão
  específica.
- **Anonimização vs pseudonimização**: helpers separados em código com
  testes que provam que anonimizado não pode ser reidentificado.
- **Cookies**: banner com aceite granular ANTES de qualquer cookie
  não-essencial (estritamente necessário pode ir direto).
- **Dados sensíveis (Art. 5º II)**: saúde/orientação/biometria/etc. exigem
  base legal específica + flag no schema + log diferenciado.

## TESTES

- Cada endpoint `/api/lgpd/*` tem teste de happy + edge + rate-limit.
- **Anonimização**: teste de irreversibilidade (não dá pra reidentificar
  via dados auxiliares razoáveis).
- **Consentimento**: revogação propaga em até 5min (cron).
- **Retention**: registros expirados são redacted em até 24h.

## sec.html

- Nova categoria `compliance_br` na matrix.
- Card "LGPD-BR status" no dashboard: Art. 18 endpoints (✓/✗), DPO
  designado, RIPD presente, política versionada.
- Tab "LGPD-BR" listando bases legais por feature.

## CHECKLIST DE PRODUÇÃO (gates Fase 5)

- [ ] DPO designado e contato público
- [ ] Base legal documentada para cada tratamento
- [ ] 6 endpoints Art. 18 implementados + testados
- [ ] Política de privacidade pública + versionada
- [ ] Cookie banner com aceite granular
- [ ] Runbook ANPD 72h em `docs/lgpd/incidente-anpd.md`
- [ ] Gate Art. 14 (menores) em cadastro
- [ ] Anonimização irreversível comprovada por teste
- [ ] Audit chain Merkle ativo para mudanças em PII

## GUARDS estáticos

- `grep` falha se aparecer CPF/RG/dados sensíveis em log de produção
- `grep` falha se cadastro novo sem campo `dataNascimento`
- `grep` falha se cookie set sem passar pelo `consent gate`
