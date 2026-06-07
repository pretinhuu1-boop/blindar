# Spec: Notifications (item #24 do ROADMAP)

> Avisar operador via Slack/Discord/email em eventos importantes do ciclo.

## Problema

Skill roda autônomo por horas/dias. Operador precisa olhar terminal +
GH PRs + `sec.html` periodicamente. Eventos críticos podem passar
despercebidos.

## Solução

Hook genérico nas fases. Operador configura provider em
`.blindar/config.yml`:

```yaml
notifications:
  enabled: true
  channels:
    - kind: slack
      webhook_url_env: BLINDAR_SLACK_WEBHOOK
      events: [crit_finding, ci_red, round_blocked, done]
    - kind: discord
      webhook_url_env: BLINDAR_DISCORD_WEBHOOK
      events: [done]
    - kind: email
      to: dev@example.com
      smtp_env: SMTP_URL
      events: [done, crit_finding]
```

## Eventos disponíveis

| Evento | Quando dispara |
|---|---|
| `started` | Fase 0 OK, pipeline começou |
| `discovery_done` | Fase 1 completa, N ATKs identificados |
| `round_done` | Cada round mergeado (config: silenciar se quiser) |
| `round_blocked` | CI vermelha por > 30min OU gate falhou |
| `crit_finding` | Adversarial review confirmou crit |
| `ci_red` | CI quebrou após mergeio |
| `adversarial_done` | Adversarial review terminou |
| `done` | Fase 6 terminou, projeto pronto |
| `error` | Erro fatal, ciclo parou |

## Formato de payload

```json
{
  "event": "crit_finding",
  "timestamp": "2026-09-01T14:30:00Z",
  "project": "owner/repo",
  "blindar_version": "0.6.0",
  "data": {
    "atk_id": "ATK-031",
    "title": "Auth bypass via header injection",
    "found_in_pr": 156,
    "lens": "security"
  },
  "next_action": "Will be queued as new round.",
  "link": "https://github.com/owner/repo/pull/156"
}
```

## Implementação proposta

Pasta nova `notifications/` no skill com:

- `slack.ps1` / `slack.sh` — POST pro webhook
- `discord.ps1` / `discord.sh` — idem
- `email.ps1` / `email.sh` — SMTP send

Cada um recebe payload JSON via stdin. Hook genérico em `pipeline/`
chama o `notify` com event+data.

## Decisões abertas

1. **Quem chama notify?** AI explicitamente em cada fase, OU hook
   automático após cada round? Primeiro = mais flexível, segundo =
   menos esquecível.
2. **Rate-limit interno?** Round done a cada 20min pode floodar.
   Sugestão: `round_done` agrupa em batch a cada hora.
3. **Auth dos webhooks**: env var aqui. Mas e se rodar em CI
   compartilhada? Vault? GH secrets?

## Por que não implementei agora

1. Requer decisão sobre **qual canal default** (Slack mais comum
   mas não universal).
2. **Webhook URL em config.yml** é risco — commitado no repo.
   Solução env var resolve mas precisa documentar bem.
3. Sem feedback real de operador, não dá pra priorizar quais
   eventos importam.

## Quando faz sentido implementar

- Operador roda blindar em background e quer alerta
- Time grande dividindo monitoramento
- Skill rodando em CI agendada (item #19 maintenance mode)
