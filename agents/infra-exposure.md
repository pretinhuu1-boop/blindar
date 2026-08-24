---
name: infra-exposure
category: security
module: 17
priority: P1
lead: runtime-lead
authority: adversary
description: |
  Exposição de infraestrutura externa: varre portas perigosas abertas (banco/cache/broker/acesso remoto) e checa o IP em blacklists DNS (DNSBL). Complementa o attack-recon, que só observa HTTP e não vê um Redis/Mongo aberto pra internet.
---

# Agente: infra-exposure (blindar ataque — exposição de infraestrutura)

> **Externo, opt-in, requer host alvo.** Vê o que o `attack-recon` (só HTTP) não
> vê: banco/cache/broker exposto direto na internet, e a reputação do IP em
> blacklists. É o buraco de "plataforma-lavanderia" clássico — Redis/Mongo/
> Postgres aberto sem auth.

## Quando ativar

- `roles: [infra-exposure]` / módulo 17 / flag `--attack`.
- Sistema **em produção** ou pré-aquisição — postura externa de rede.
- Recorrente como health-check externo.

## Pré-condições

- Host **de sua propriedade** OU com autorização explícita (é conexão TCP ativa,
  ainda que não-destrutiva).
- Nenhum acesso privilegiado (observa de fora).

## O que descobre

| Vetor | Como | Severidade |
|---|---|---|
| Banco exposto (MySQL/Postgres/Mongo/Elastic/MSSQL) | TCP connect | crit |
| Cache exposto (Redis/Memcached) | TCP connect | crit |
| Message broker (RabbitMQ) | TCP connect | high |
| Acesso remoto (SSH/Telnet/RDP) | TCP connect | high |
| App/dev exposto direto (3000/5000/8000/8888) | TCP connect | med |
| IP em blacklist DNS (Spamhaus/SpamCop/Barracuda/SORBS) | DNSBL | high |

Só reporta porta **confirmada OPEN** (handshake TCP completo). `ECONNREFUSED`/
`ECONNRESET` = fechada; timeout = filtrada; qualquer outro erro = **não testável**
(nunca lido como "seguro").

## Procedimento

```bash
node ~/.claude/skills/blindar/scripts/infra-scan.mjs --target seu-host.com
# ou uma porta específica:
node ~/.claude/skills/blindar/scripts/infra-scan.mjs --target seu-host.com:6379 --json
```

Exit 1 se houver achado crit/high; 0 se limpo. Cada finding traz risco +
recomendação (fechar no firewall, bind 127.0.0.1, exigir auth/TLS). Combine com
`blindar-report.mjs reproduzir` para os passos de confirmação.

## Fora de escopo

- Não envia payload de aplicação (isso é `pentest-active`, gated por autorização).
- GeoIP e timing detalhado ficam no Sentinela (via `sentinela-bridge`).
