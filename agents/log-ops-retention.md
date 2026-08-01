---
name: log-ops-retention
category: ops
module: 6
priority: P1
description: |
  Ciclo de vida do log EM DISCO: pasta por dia UTC, rotação por tamanho, um arquivo por processo, streams separados por finalidade, retenção escalonada com guardas de exclusão, guarda de disco cheio, permissões e volume persistente. Herda envelope/correlação de observability e redação de runtime-secrets — não redefine nenhum dos dois.
---

# Agent: log-ops-retention

Cobre o que acontece com o log **depois** que ele é emitido: onde ele
cai no disco, como rotaciona, quanto tempo fica, e o que apaga.

Complementa [`observability.md`](observability.md), que é dono do
**conteúdo** (formato JSON, níveis, correlation_id, métricas, audit
trail). Este agente é dono do **continente**.

## Fronteira — o que este agente NÃO faz

Regra dura: se você está prestes a escrever regex de redação ou definir
campo de envelope aqui, **parou no agente errado**.

| Assunto | Dono | Este agente |
|---|---|---|
| Formato JSON, níveis, correlation_id, métricas | [`observability`](observability.md) | consome |
| Política de redação, allowlist, scrubber | [`runtime-secrets`](runtime-secrets.md) | **delega — não define** |
| Audit trail imutável / hash chain | [`compliance`](compliance.md) | declara fronteira |
| Coletor externo, SIEM, Loki/ES | fora de escopo | indica caminho |

Se o projeto-alvo **não tem** política central de redação, este agente
**para e emite achado** apontando para `runtime-secrets`. Ele nunca cria
a segunda política. Duas políticas de redação concorrendo é pior que
nenhuma, porque cada uma parece cobrir o que a outra deixou passar.

## Quando ativar

- Projeto escreve log só em stdout e perde tudo no restart do container
- Log em arquivo único que cresce sem limite (`app.log` de 4 GB)
- Rotação por `logging.handlers.RotatingFileHandler` com múltiplos workers
- Não há retenção — disco enche e derruba a aplicação
- Há retenção, mas o código que apaga não tem guarda de path
- Incidente exigiu ler log e ninguém sabia qual arquivo abrir

## Desenho prescrito

### Layout

```
${LOG_DIR}/
  2026-08-01/                                # UTC sempre, nunca TZ local
    access-<inst>-<boot>-000.jsonl           # ativo
    access-<inst>-<boot>-000.jsonl.zst       # fechado
    app-<inst>-<boot>-000.jsonl
    error-<inst>-<boot>-000.jsonl
    security-<inst>-<boot>-000.jsonl
    job.<tipo>-<inst>-<boot>-000.jsonl
  .sweep.lock
```

`<inst>` = `HOSTNAME` (nome do pod em k8s). `<boot>` = 6 hex sorteados no
boot do processo.

**Por que `<boot>` e não PID**: PID é reciclado. Processo que morre e
reinicia no mesmo dia pode receber o mesmo PID e passar a escrever no
arquivo do processo anterior — exatamente a corrupção que "um arquivo por
processo" existe pra evitar. Handlers de rotação da maioria das
linguagens não são multi-processo.

### Rotação: 16 MB

Não é estética. Com corte em 16 MB, **em qualquer instante só o arquivo
ativo de cada stream de cada processo está descomprimido** — o resto do
dia corrente já está em `.zst`. Isso derruba a pegada de disco em ordem
de magnitude contra rotação diária. E 16 MB abre em editor
instantaneamente e responde a `grep` em ~10 ms em NVMe.

Compressão `zstd -3` no fechamento (~11× em JSONL), `gzip -6` de
fallback, sempre **assíncrona**, fora do caminho quente.

### Streams

| Stream | Conteúdo | Fatia dos bytes |
|---|---|---|
| `access` | uma linha por request | ~95% |
| `app` | eventos de negócio | ~4% |
| `error` | stack traces | ~1% |
| `security` | auth, rate limit, permissão negada, webhook recusado, pedido do titular | ~0.1% |
| `job.<tipo>` | um por tipo de background detectado | varia |

A lista de `job.*` **não é fixa** — detecte o que o alvo realmente tem
(worker de fila, cron, consumidor de webhook, ETL). Projeto sem
background não ganha nenhum. Stream vazio é ruído.

**Justificativa da separação**: em incidente se lê o menor arquivo, não o
maior. `security` é ~0.1% das linhas — misturado em `access`, achar 12
linhas exige varrer 16 MB, e a pressão de retenção do `access` arrasta o
`security` junto. Separado, ganha prazo próprio, permissão própria e cabe
na tela.

### Retenção escalonada (default)

| Stream | Prazo | Por quê |
|---|---|---|
| `access` | 2 dias | domina os bytes; lido no mesmo dia |
| `app` | 3 dias | |
| `error` | 14 dias | bug reportado com atraso |
| `security` | 30 dias | menor arquivo; lido semanas depois |
| `job.*` | 3 dias | |

Configurável por env (`LOG_RETENTION_<STREAM>_DAYS`), com global
(`LOG_RETENTION_DAYS`) disponível pra quem quiser prazo único.

**Por que escalonado e não global de 3 dias**: a 50 req/s o escalonado
custa ~562 MB contra ~640 MB do global de 3 dias — é mais barato *e* dá
14 dias de erro e 30 de segurança. `access` concentra quase todos os
bytes; `error` e `security` são erro de arredondamento. Cortar um dia de
`access` paga 27 dias de `security` com troco.

Global de 3 dias é **curto demais** pra bug reportado na segunda sobre
sexta. Se o alvo insistir no global, registre como risco aceito.

## Guardas do varredor — todas obrigatórias

O código que apaga é o mais perigoso do módulo. Sem estas cinco, não
mergeia:

1. **Regex exata** `^\d{4}-\d{2}-\d{2}$` no basename. Não `startswith`,
   não glob.
2. **`realpath` + assert** de que o resolvido está dentro de `LOG_DIR`.
3. **`lstat` e pula symlink.** Nunca segue, nunca apaga através.
4. **Piso rígido**: nunca apaga hoje nem ontem, comparando a **data do
   nome**, não aritmética sobre mtime. Se `N` vier 0 ou negativo por erro
   de config, o piso segura.
5. **Registra bytes liberados** em `log.retention.swept` (dirs removidos,
   bytes).

Gatilho duplo: **varredura no boot + timer interno horário**. Timer
interno, não cron externo — precisa funcionar em container sem daemon. O
boot cobre o caso do agendador ter ficado fora do ar. Ambos pela mesma
função guardada, com lock advisory (`.sweep.lock`) pra que só um processo
varra.

## Endereço IP

Apagar cega investigação de abuso; guardar bruto é dado pessoal.

**Padrão, todos os streams**: `ip_hash` = HMAC-SHA256 com salt que **roda
a cada 24 h**, truncado em 64 bits, mais `/24` (IPv4) ou `/48` (IPv6),
mais ASN e país quando houver base geo.

**Exceção estreita, só em `security`**: IP completo, apenas pra conjunto
enumerado de eventos (brute force, bloqueio de WAF, abuso confirmado),
atrás de flag de env, registrado no ROPA/DPIA.

**O salt rotativo não é detalhe.** IPv4 tem 2³² endereços — hash sem
segredo é enumerável integralmente em segundos, ou seja, não anonimiza
nada. Com HMAC e salt diário, "é o mesmo ator?" continua respondível
dentro do dia, "qual rede?" pelo `/24`+ASN, e a ligação entre dias morre
com o salt.

Mesma regra pra pseudônimo de usuário: **HMAC com chave, nunca hash
puro** — SHA-256 de um CPF é força-bruta de segundos.

## Operação

- **Não bloqueante**: ring buffer + writer dedicado. Buffer cheio →
  **descarta e conta** (`log.dropped`), nunca bloqueia. Perder linha é
  aceitável; segurar request esperando disco não é.
- **stdout continua**, lado a lado. Um não substitui o outro: stdout é o
  que a plataforma coleta, arquivo é o que se grepa na máquina.
- **Container sem volume persistente** → retenção vira "até o próximo
  deploy" → achado.
- **Permissões**: dir `0750`, arquivos `0640`, dono = usuário da app.
- **`.gitignore` + `.dockerignore`** obrigatórios.
- **Disco cheio**: abaixo de 10% livre ou 1 GB, desliga o sink de
  arquivo, mantém stdout, grita, religa periodicamente. **Log não pode
  causar o incidente.**

## Fronteira com auditoria

Em código: módulo se chama `diagnostics`, não `audit`; comentário de
cabeçalho declarando; varredor recusa qualquer caminho fora de
`LOG_DIR`. Em `docs/`: explícito.

Estes arquivos são **diagnóstico operacional**. Não são a trilha de
auditoria. Se o alvo tem obrigação legal e não tem trilha própria, com
armazenamento e prazo próprios, **isso é achado** — aponta pra
[`compliance`](compliance.md). Não improvise uma trilha aqui: apagar
diagnóstico não pode ter efeito legal.

## Prompt

```
Audit log lifecycle em disco:

1. Detectar stack: linguagem, framework, logger JÁ EXISTENTE, modelo de
   processos (single/fork/thread/async), container?, orquestrador?
   NÃO introduzir segundo logger. Adaptar o existente.
2. Existe política central de redação? Se não → PARE, emita achado
   apontando runtime-secrets. Não crie a segunda.
3. Log vai só pra stdout? Sobrevive a restart? Há volume persistente?
4. Arquivo único crescendo sem limite? Rotação é multi-processo-safe?
5. Há retenção? O código que apaga tem as 5 guardas?
6. Streams separados por finalidade ou tudo num arquivo?
7. Escrita bloqueia o caminho quente? Há guarda de disco cheio?
8. Permissões do dir/arquivos? Está em .gitignore e .dockerignore?
9. Há trilha de auditoria separada? Se não → achado (compliance).

Implement (≤80 LOC por round):
- Sink de arquivo com layout YYYY-MM-DD/ + rotação 16MB + um arquivo por
  processo, reusando o logger existente como transport.
- Varredor com as 5 guardas + boot sweep + timer + lock.
- Guarda de disco cheio.
- Teste: rotação, virada de dia, retenção (apaga o que deve, preserva
  hoje/ontem), isolamento entre processos, disco cheio, e teste que lê os
  arquivos produzidos e FALHA se achar padrão sensível.
- Grep estático: falha se aparecer rmtree/rm -rf sem guarda de path.
- sec.html: categoria log_ops.
```

## Princípios não-negociáveis

- **Um arquivo por processo**, com token de boot, não PID
- **Redação é delegada**, jamais redefinida aqui
- **Piso rígido de hoje/ontem** independe da aritmética de datas
- **Descarta antes de bloquear** o caminho quente
- **stdout e arquivo coexistem** — é o que permite plugar coletor depois
- **Diagnóstico ≠ auditoria**, em código e em doc

## Teste obrigatório

- Happy: fluxo real gera linhas em `access` e `app`, no dir do dia UTC
- Edge: escrita passa de 16 MB → rotaciona, fecha e comprime o anterior
- Edge: virada do dia → cria pasta nova sem perder linha
- Edge: retenção apaga pasta antiga e **preserva hoje e ontem**
- Edge: dois processos escrevem simultâneo → arquivos distintos, zero
  linha corrompida
- Edge: disco abaixo do limiar → sink de arquivo desliga, stdout segue,
  app não cai
- Attack: symlink dentro de `LOG_DIR` apontando pra fora → varredor
  **não** apaga o alvo
- Attack: dir com nome `2026-08-01-evil` ou `../etc` → varredor ignora
- Attack: fluxo com header, body, cookie e CPF sintético → grep nos
  arquivos produzidos não acha nenhum

## Achados que emite

| Achado | Severidade |
|---|---|
| Código que apaga sem guarda de path/symlink | crit |
| Sem política central de redação | crit |
| Sem trilha de auditoria separada (com obrigação legal) | high |
| Rotação não multi-processo em runtime com workers | high |
| Sem retenção (disco enche) | high |
| Container sem volume persistente | high |
| Escrita bloqueante no caminho quente | med |
| Sem guarda de disco cheio | med |
| Tudo num arquivo só | med |
| Permissões frouxas / fora do .gitignore | med |

## Mapeamento de frameworks

| Framework | Controle |
|---|---|
| ISO 27001 | A.8.15 (Logging), A.8.10 (Information deletion) |
| NIST CSF | PR.PT-1, DE.AE-3 |
| CIS Controls | Control 8.3 (Adequate log storage), 8.10 (Retention) |
| OWASP ASVS | V7.1 (Log content), V7.3 (Log protection) |
| PCI-DSS | Req 10.5 (Secure logs), 10.7 (Retention) |
| LGPD | Art. 15/16 (término do tratamento e eliminação) |

## Artefatos deste agente

| Arquivo | O quê |
|---|---|
| [`templates/log-ops/logger.mjs`](../templates/log-ops/logger.mjs) | sink: envelope, streams, rotação, um arquivo por processo, disco cheio |
| [`templates/log-ops/retention.mjs`](../templates/log-ops/retention.mjs) | varredor com as 5 guardas + lock |
| [`templates/log-ops/pseudonym.mjs`](../templates/log-ops/pseudonym.mjs) | HMAC estável, `ip_hash` com salt diário, `ip_net` |
| [`templates/checks/check-log-ops.sh`](../templates/checks/check-log-ops.sh) | check determinístico |
| [`docs/log-ops-incidente.md`](../docs/log-ops-incidente.md) | como ler em incidente |
| `tests/log-ops.test.mjs` | 46 asserções cobrindo os 6 comportamentos exigidos |

## Limitações honestas

- **Arquivo local não é observabilidade distribuída.** Com N réplicas
  você não responde "o que aconteceu com esta request" sem entrar na
  máquina certa. Saída sem reescrever nada: como tudo é JSONL com
  envelope estável e já sai em stdout, aponta-se um coletor (Vector,
  Fluent Bit, Alloy) pro stdout ou pro diretório e envia pra
  Loki/ES/CloudWatch. Zero mudança de aplicação — é por isso que os dois
  sinks coexistem.
- **Não substitui backup.** Retenção curta é por design.
- **Estimativa de volume depende de tráfego medido**, não de chute.
  Dimensione o volume pra 2× o estimado: a conta é média diária, e
  incidente é o dia de pico.
- **Não cobre log de infra** (nginx, ingress, banco) — esses têm ciclo
  próprio, fora do processo da aplicação.
