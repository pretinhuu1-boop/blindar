# Fase 5 — Production checklist

**Duração**: ~3 min

## Quando roda

Após adversarial review (Fase 4) limpa: **0 crit + ≤2 high** confirmados.

## Gates

| Gate | Como | Bloqueia |
|---|---|---|
| DDoS | rate-limit global + boot guard proxy | sim |
| Observability | `/health/{live,ready,deep}` + audit chain | sim |
| Backup at-rest | secrets não-plaintext | sim |
| Key rotation | `docs/key-rotation.md` | warn |
| Incident response | `docs/incident-response.md` | warn |
| Secret scan CI | gitleaks ou equivalente | sim |

## Gates extras (se LGPD-BR detectado)

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
