# Fase 6 — Production checklist

**Duração**: ~3 min

## Quando roda

Após adversarial review (Fase 5) limpa: **0 crit + ≤2 high** confirmados.

## Filtragem por módulo selecionado (v0.8+)

Cada gate abaixo está associado a um módulo do `pipeline/MODULE-MAP.json`.
**Antes de rodar os gates**, ler `.blindar/config.yml > selected_modules` e
aplicar só os que correspondem a módulos ativos. Gates de módulos não-
selecionados ficam marcados como `skipped-by-user-selection` (não bloqueia
release, mas aparece no relatório final).

Gates dos módulos **mandatórios** (1, 2, 11, 12, 15) sempre rodam.

| Módulo | Gate (rotulado) |
|---|---|
| 2 (sempre) | Secret scan CI (gitleaks), key rotation, incident response |
| 4 (saas/ecom/api) | DDoS rate-limit + boot guard proxy |
| 6 (saas/ecom/api) | Observability `/health/{live,ready,deep}` + audit chain |
| 7 (tem-DB) | Backup at-rest + restore testado |
| 8 (sens=A/M) | Gates LGPD/ANPD (ver abaixo) |
| 10 (ui) | Lighthouse ≥ 90 em 4 pilares (Perf/A11y/BP/SEO) |
| 11 (sempre) | Funcional E2E — todo botão visível dispara algo real |
| 12 (sempre) | Anti-mock — zero `console.log`, TODO, mocks em produção |
| 13 (rigor≠mvp) | Load test no termination (k6/Artillery) |
| 14 (sempre) | `.env.example` sync, scripts iniciar.bat/sh, README mínimo |
| 15 (sempre) | Pentest automatizado verde (SAST/DAST/SCA) |

## Gates baseline (sempre rodam, módulo 2)

| Gate | Como | Bloqueia |
|---|---|---|
| Secret scan CI | gitleaks ou equivalente | sim |
| Key rotation | `docs/key-rotation.md` | warn |
| Incident response | `docs/incident-response.md` | warn |

## Gates extras (se LGPD-BR detectado / módulo 8 ativo)

Ver [`agents/compliance-lgpd-br.md`](../agents/compliance-lgpd-br.md):

- [ ] DPO designado e contato público
- [ ] Base legal documentada para cada tratamento
- [ ] 6 endpoints Art. 18 implementados + testados
- [ ] Política de privacidade pública + versionada
- [ ] Cookie banner com aceite granular
- [ ] Runbook ANPD 72h em `docs/lgpd/incidente-anpd.md`
- [ ] Gate Art. 14 (menores) em cadastro
- [ ] Anonimização irreversível comprovada por teste
- [ ] Audit chain Merkle ativo para mudanças em PII

## Comportamento

- Faltando `bloqueia: sim` → mais rounds.
- Faltando `warn` → registra em `.accept-risk.md` (ver
  [`templates/accept-risk.md`](../templates/accept-risk.md)) e segue.
