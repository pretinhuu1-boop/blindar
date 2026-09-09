---
name: container-hardening
category: devops
module: 18
priority: P0
lead: platform-lead
authority: implement
description: |
  Container rodando como root e sem teto de recurso. Dois defeitos independentes, os dois invisíveis enquanto tudo vai bem: root encurta a distância de uma RCE até o host, e ausência de limite faz um serviço derrubar os vizinhos da máquina.
---

# Agent: container-hardening

Dois problemas distintos, os dois invisíveis enquanto tudo vai bem.

**ROOT.** `USER` ausente no Dockerfile significa uid 0 dentro do container. Uma
escrita arbitrária que seria "gravar num diretório do app" vira "gravar em
qualquer lugar do rootfs", e o caminho até o host fica curto demais — em
conjunto com uma montagem de volume, com o socket do Docker, ou com uma falha de
runtime.

**SEM LIMITE.** Container sem `mem_limit`/`cpus` come toda a máquina. Numa VPS com
vizinhos — o caso normal — um vazamento de memória no seu serviço derruba o banco
de outro projeto. **O sintoma aparece no vizinho**, e a investigação começa no
lugar errado.

## O que o check já garante

[`check-container-hardening.sh`](../templates/checks/check-container-hardening.sh)
lê Dockerfile e compose. Nada aqui exige o host no ar.

| Situação | Severidade |
|---|---|
| Dockerfile sem `USER`, ou com `USER root` | **high** |
| `privileged: true` no compose | **high** |
| Compose sem nenhum limite de recurso | **med** |
| Bloco de recursos sem teto de memória | **med** |
| Sem teto de CPU | **low** |
| Sem `no-new-privileges` | **low** |
| Sem `cap_drop` | **low** |
| Rootfs sem `read_only: true` | **low** |

Auto-skip em projeto sem Dockerfile e sem compose.

## A base razoável

```yaml
services:
  api:
    read_only: true
    mem_limit: 512m
    cpus: 0.5
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    tmpfs:
      - /tmp
```

E no Dockerfile, antes do `CMD`:

```dockerfile
RUN addgroup --system app && adduser --system --ingroup app app
USER app
```

`read_only: true` exige `tmpfs` para o que a aplicação escreve de fato — logs em
arquivo, cache, upload temporário. Ligar sem isso quebra na primeira escrita.

## O teto de memória e o runtime

Limite de container sem limite de heap é meia solução: o processo cresce até o
teto do cgroup e o kernel o mata (OOMKill), sem chance de log nem de encerramento
gracioso. Combine com o limite do runtime — `--max-old-space-size` no Node,
`GOMEMLIMIT` no Go, `-Xmx` na JVM — sempre **abaixo** do teto do container.

## O que só se prova no host

| Verificar | Como |
|---|---|
| O processo roda mesmo como não-root | `docker exec <c> id` |
| O limite está aplicado | `docker stats` — compose `mem_limit` é ignorado em modo swarm |
| O socket do Docker não está montado | montar `/var/run/docker.sock` anula todo o resto |
| Não há `--privileged` no comando de subida | o compose pode estar certo e o `docker run` não |
