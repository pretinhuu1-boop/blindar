# agent: observability

Logs, métricas, traces, audit trail. Cobre técnica #7 do baseline
(monitoramento e auditoria).

Complementa [`compliance.md`](compliance.md) — este foca em sinais
operacionais; compliance foca em audit chain para PII.

## Quando ativar

Round cujo gap envolve:
- Endpoint sem log estruturado
- Erro silencioso (try/except sem log)
- Falta de métrica em operação crítica
- Audit trail incompleto
- Logs sem correlation ID

## Prompt

```
Audit observability:
1. Logs estruturados (JSON) com correlation_id propagado entre serviços.
2. Níveis corretos: INFO operação normal, WARN degradação, ERROR falha
   real, CRITICAL paginação. Nada de print/console.log em prod path.
3. PII redacted em todo log (helper central, grep estático).
4. Métricas: latência (p50/p95/p99), error rate, throughput, saturação
   por endpoint crítico.
5. Health endpoints: /health/live (responde), /health/ready (pronto pra
   tráfego), /health/deep (deps OK).
6. Audit trail para ações privilegiadas: who, what, when, from-where,
   result, hash da entrada anterior (chain).
7. SIEM-friendly: campos padronizados (ECS / OTel semantic conventions).

Implement (≤80 LOC):
- Helper estruturado se não existir.
- Cobertura dos pontos críticos identificados.
- Teste: log emitido em formato esperado + sem PII.
- Grep estático: falha em print(/console.log(/logger.info(...PII...
- sec.html: ATK → covered, atualiza tab Métricas com baseline atual.

Não inventar novas dependências de SIEM. Stdout JSON é suficiente —
infra coleta.
```

## Princípios

- **Log estruturado obrigatório.** Free-text impossibilita query.
- **Correlation ID propagado.** Request entra → ID gerado → atravessa
  todos os serviços downstream → aparece em todo log relacionado.
- **PII jamais em log.** Helper redact centralizado. Grep falha se vier
  de path de produção.
- **Métrica de erro != log de erro.** Métrica permite alarme;
  log permite debug.
- **Audit trail é append-only.** Mesma regra de compliance.md (hash chain).

## Teste obrigatório

- Happy: requisição emite logs com correlation_id
- Edge: erro emite log nível ERROR + métrica error_count++
- Attack: tentativa de log com CPF/senha → redacted automaticamente

## Mapeamento de frameworks

| Framework | Controle |
|---|---|
| ISO 27001 | A.12.4.x (Logging and monitoring) |
| NIST CSF | DE.AE, DE.CM (Detect functions) |
| CIS Controls | Control 8 (Audit log management) |
| PCI-DSS | Req 10 (Track and monitor) |
| SOC 2 | CC7.2, CC7.3 |
