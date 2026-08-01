# Como ler os logs em incidente

Guia operacional do esquema implantado por
[`agents/log-ops-retention.md`](../agents/log-ops-retention.md).

> **Estes arquivos são diagnóstico operacional. NÃO são a trilha de
> auditoria.** Eles são apagados por retenção curta. Se você precisa provar
> o que aconteceu para efeito legal ou regulatório, a fonte é a trilha de
> auditoria, que vive em armazenamento próprio com prazo próprio. Apagar o
> que está aqui não pode ter efeito legal.

## Onde as coisas estão

```
${LOG_DIR}/2026-08-01/                       ← pasta por dia, UTC
  access-<inst>-<boot>-000.jsonl             ← ativo
  access-<inst>-<boot>-000.jsonl.gz          ← fechado, comprimido
  app-…  error-…  security-…  job.<tipo>-…
```

`<inst>` é o host/pod. `<boot>` identifica o **processo**. Dois arquivos com
`<boot>` diferente no mesmo dia são dois processos — réplicas, ou reinícios.

A data da pasta é **UTC**, não seu fuso. Um incidente às 21h em São Paulo
está na pasta do dia seguinte.

## Qual stream responde qual pergunta

| Pergunta | Stream | Por quê |
|---|---|---|
| "essa request chegou? com que status? quanto demorou?" | `access` | uma linha por request |
| "o pedido foi criado? o pagamento passou?" | `app` | eventos de negócio |
| "o que explodiu, e onde?" | `error` | stack traces |
| "alguém tentou entrar? foi bloqueado? quem pediu os dados dele?" | `security` | auth, rate limit, permissão, webhook, titular |
| "a fila processou? o cron rodou?" | `job.<tipo>` | um por tipo de background |

**Comece pelo menor arquivo que possa conter a resposta.** `security` é ~0,1%
das linhas; `access` é ~95%. Se a pergunta é de segurança, abrir `access`
primeiro é desperdiçar o tempo do incidente.

## Receitas

Tudo é JSON Lines — uma linha, um evento. `jq` funciona direto; nos `.gz` use
`zcat`/`gunzip -c`.

**Seguir uma request específica pelo id de correlação:**

```bash
zgrep -h '"req_id":"01J7X…"' logs/2026-08-01/*.jsonl* | jq -s 'sort_by(.ts)'
```

Isso atravessa todos os streams e todos os processos do dia — é o caminho
mais rápido para reconstruir uma jornada.

**Erros das últimas horas, agrupados por evento:**

```bash
cat logs/2026-08-01/error-*.jsonl | jq -r .event | sort | uniq -c | sort -rn
```

**Requests de um tenant, com status ≥ 500:**

```bash
cat logs/2026-08-01/access-*.jsonl | jq -c 'select(.tenant_id=="t_123" and .status>=500)'
```

**O mesmo ator voltou?** O `actor` é pseudônimo estável (HMAC), então dá para
correlacionar sem que o valor real esteja no arquivo:

```bash
zgrep -h '"actor":"u_ab12cd34"' logs/*/*.jsonl* | jq -r '[.ts,.event] | @tsv'
```

**Mesmo IP?** `ip_hash` é estável **dentro do dia** — o salt roda a cada 24 h,
então o mesmo IP tem hash diferente amanhã. Para atravessar dias, use
`ip_net` (o `/24` ou `/48`), que é estável:

```bash
cat logs/2026-*/security-*.jsonl | jq -r 'select(.ip_net=="203.0.113.0/24") | .event' | sort | uniq -c
```

## O que você NÃO vai encontrar, e o que usar no lugar

| Não está lá | Use |
|---|---|
| corpo de request/response | `body_bytes` (tamanho), `event` |
| header `Authorization`, cookie | nada — é intencional |
| query string completa | path template + nomes dos parâmetros |
| CPF, e-mail, nome, documento | `actor` (pseudônimo) |
| IP bruto | `ip_hash` + `ip_net`; bruto só em `security`, e só para eventos de abuso |

Se você precisa do valor real para investigar, o caminho é a trilha de
auditoria ou o banco — não estes arquivos.

## Prazos (default)

| Stream | Prazo |
|---|---|
| `access` | 2 dias |
| `app` | 3 dias |
| `error` | 14 dias |
| `security` | 30 dias |
| `job.*` | 3 dias |

Configurável em `LOG_RETENTION_<STREAM>_DAYS`, com `LOG_RETENTION_DAYS` como
global.

**Consequência prática:** um bug reportado na segunda sobre a sexta ainda tem
`error` e `security`, mas o `access` daquele dia já foi. Se você precisa
regularmente do `access` além de 2 dias, aumente esse prazo especificamente —
ele é que domina o disco, então é uma decisão de custo consciente, não um
descuido.

## Quando o log some ou falta

- **Pasta de hoje vazia e nada em disco** → o sink de arquivo pode ter sido
  desligado por disco cheio. Procure `log.file_sink.disabled` no stdout: ele
  continua saindo mesmo com o arquivo desligado.
- **Linhas faltando sob carga** → o buffer descarta antes de bloquear, por
  desenho. `log.dropped` conta quantas. Log nunca segura request.
- **Pasta antiga desapareceu** → retenção. `log.retention.swept` registra o
  que foi removido e quantos bytes liberou.
- **Só um processo aparece** → cada processo escreve no seu arquivo; procure
  outros `<boot>` no mesmo diretório.

## Limite: mais de uma réplica

Arquivo local **não é observabilidade distribuída**. Com N réplicas você não
responde "o que aconteceu com esta request" sem saber em qual máquina ela
caiu.

A saída não exige reescrever nada: as linhas já são JSONL com envelope
estável e já saem em `stdout`. Aponte um coletor (Vector, Fluent Bit, Alloy)
para o stdout ou para o diretório e envie para Loki/Elasticsearch/CloudWatch.
Nenhuma mudança na aplicação — é exatamente por isso que os dois sinks
coexistem.
