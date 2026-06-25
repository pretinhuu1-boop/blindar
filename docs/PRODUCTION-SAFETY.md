# Production Safety — garantias ao rodar em software em produção

> Duas perguntas que todo operador faz antes de apontar o blindar pra um
> sistema real: **(1) posso quebrar banco/config?** e **(2) a qualidade é a
> mesma em qualquer modelo?** Este documento responde e codifica as garantias.

---

## 1. Garantia de não-quebrar produção

**Princípio:** o blindar opera no **código via git**, não no seu banco/infra
de produção. Ele **propõe** mudanças em PR; um humano (ou CI) aplica.

### O que protege você (gates que já existem)

| Garantia | Como funciona | Onde |
|---|---|---|
| **Dry-run** | `dry_run: true` → simula, mostra o que faria, **não cria PR nem mergeia** | `schemas/config.schema.json` |
| **Repo limpo obrigatório** | Preflight **para** se há mudanças não-commitadas | `scripts/preflight.*` |
| **Branch + PR por round** | Nunca commita direto na main; você revisa cada PR | princípio não-negociável |
| **CI verde antes de merge** | Teste vermelho = não entra | quality gate |
| **Não quebra defesa existente** | Guard estático grep barra regressão silenciosa | princípio |
| **Backup antes de migration** | Agente `backup-recovery` exige backup testado | `agents/backup-recovery.md` |
| **Soft-delete** | Nunca hard-delete em entidade principal | princípio |

### O que o blindar NÃO faz

- ❌ Conectar no seu Postgres/Mongo de produção e rodar `DROP`/migration.
- ❌ Aplicar mudança sem PR revisável.
- ❌ Tocar em `.env`/secrets de produção (só aponta que existem e como rotacionar).

Migrations viram **arquivo num PR**. Quem aplica é você/CI — **em staging primeiro.**

### Workflow seguro obrigatório (produção)

```
1. dry_run: true          → veja o que ele faria, sem efeito
2. Rode de verdade        → gera PRs pequenos, revisáveis
3. Revise cada PR         → você aprova, não ele
4. Aplique em STAGING     → nunca direto em produção
5. Backup testado         → antes de qualquer migration
6. Produção               → só depois de staging verde + backup
```

**Regra de ouro:** nunca aponte o blindar direto pra produção sem dry-run +
staging + backup. A camada determinística (checks/gates) te protege de mergear
lixo, mas a decisão de aplicar em produção é **sua**.

---

## 2. Garantia de qualidade por modelo (Haiku / Sonnet / Opus)

**Resposta honesta:** o raciocínio **não** é igual entre modelos — é física,
não bug. Mas há uma parte que **é** idêntica em qualquer modelo, e um
mecanismo pra dar "up" quando o modelo é menor.

### Duas camadas — só uma depende do modelo

| Camada | Depende do modelo? | Exemplos |
|---|---|---|
| **Determinística** | ❌ **Idêntica em qualquer modelo** | scanners, checks, gates, schemas, `reproducibility.js`, `sbom-build.js`, `race-fuzz.js`, termination matemático |
| **Raciocínio** | ✅ Haiku < Sonnet < Opus | entender finding, escrever fix, julgar adversarial |

Por isso, ao rodar em modelo menor, você sente "parou muita coisa": o
**orquestrador** (sessão do Claude Code) raciocina pior. Os **gates** seguem
firmes — eles não deixam passar lixo — mas a geração de fix degrada.

### Matriz de modelo recomendada

| Cenário | Sessão Claude Code | `BLINDAR_BUDGET` | `BLINDAR_MIN_MODEL` |
|---|---|---|---|
| **Produção / compliance** | Opus | `smart` ou `premium` | `claude-opus-4-8` |
| **Staging / interno** | Sonnet | `smart` | `claude-sonnet-4-6` |
| **Triagem / exploração** | Haiku/Sonnet | `tight` | (nenhum) |

### Preset `smart` (recomendado) — v0.43

`BLINDAR_BUDGET=smart` aplica os defaults inteligentes automaticamente:
**qualidade onde dói, barato onde não.** Igual ao `standard`, mas com uma
diferença-chave: quando o stake é **incerto** (tier desconhecido), sobe pra
Sonnet em vez de Haiku — não economiza na dúvida.

| Tier | `standard` | `smart` |
|---|---|---|
| triage | Haiku | Haiku |
| analysis | Sonnet | Sonnet |
| security / strategic | Opus | Opus |
| **incerto/desconhecido** | **Haiku** (barato) | **Sonnet** (seguro) |

```bash
export BLINDAR_BUDGET=smart
export BLINDAR_MIN_MODEL=claude-opus-4-8   # opcional: piso pra produção
blindar
```

### O mecanismo de "up": piso de modelo (`BLINDAR_MIN_MODEL`) — v0.43

O `_token_governor.sh` já fixa Opus nos agentes de segurança nas suas
**sub-chamadas governadas**. O **piso** vai além: garante que **nada** roda
abaixo de um modelo mínimo, **mesmo** numa sessão Haiku ou budget tight.

```bash
# Sessão em Haiku, mas toda análise crítica é delegada a Opus:
export BLINDAR_MIN_MODEL=claude-opus-4-8
blindar

# Resultado (governor):
#   triage   → opus   (subiu de haiku)
#   analysis → opus   (subiu de sonnet)
#   security → opus   (já era)
```

**Como funciona:** o orquestrador (sessão) só coordena; o raciocínio pesado
(análise de segurança, fix) é feito por **sub-chamadas à API** que o governor
roteia pro modelo do piso. Assim, mesmo um cérebro orquestrador fraco delega o
trabalho difícil pra um modelo forte.

**Limite honesto:** o piso melhora as sub-chamadas governadas, não transforma o
orquestrador. Pra produção, o ideal continua sendo **rodar a sessão em Opus**.
O piso é a rede pra quando isso não é possível.

### Compensações automáticas em modelo menor (recomendado)

Quando forçado a modelo menor, apoie-se mais na camada determinística:

1. Ative **todos** os checks determinísticos (`install-deterministic-checks.sh`).
2. Exija **revisão humana** em todo PR (não auto-merge).
3. Use `BLINDAR_MIN_MODEL` pra subir o crítico.
4. Rode `reproducibility.js --check` entre 2 runs — se divergir muito, o
   modelo está instável demais pra esse projeto; suba o tier.

---

## Resumo de uma linha

- **Banco/produção:** o blindar nunca toca direto — propõe PR, você aplica
  via staging + backup. Garantido por dry-run + branch + CI + backup-recovery.
- **Modelo:** determinístico é igual em todos; raciocínio não. Use
  `BLINDAR_MIN_MODEL=claude-opus-4-8` pra subir o crítico em sessão menor, e
  rode produção em Opus quando puder.
