# Camada determinística e intelligence system

> Referência do `blindar`, extraída do `SKILL.md` para não ocupar o
> caminho quente. Carregue quando a etapa exigir.

## Deterministic Layer (⭐ v0.22)


Camada de scripts shell que **materializa agentes em checks executáveis**
+ CI workflow que bloqueia merge. Resolve "blindar não garante 100% no
modo AUTO" — agora roda **independente da diligência do LLM**.

Templates em [`templates/checks/`](../templates/checks/). Instalador:

```bash
cd seu-projeto
bash ~/.claude/skills/blindar/scripts/install-deterministic-checks.sh
```

Resultado no projeto-alvo:
- `scripts/blindar/*.sh` — **117 checks executáveis** (103 shell puro + 14
  `.api.sh`). O instalador copia `templates/checks/*.sh` inteiro, então a conta
  cresce com o repositório em vez de ficar congelada aqui.

  > Esta linha dizia "8 checks executáveis" até a v0.79 — número da v0.22, que
  > ficou parado por 57 versões. Documentação que envelhece em silêncio produz
  > exatamente o tipo de conclusão errada que este projeto tenta evitar: quem
  > lesse a referência concluiria que o blindar mede 8 coisas.

- **5 deles são DINÂMICOS** (v0.79): exercitam o sistema no ar em vez de ler o
  repositório — `chaos-run`, `load-curve`, `redteam-origin`, `deploy-identity`,
  `failure-ux`. Sem alvo eles saem `skipped` com motivo, e a dimensão fica
  `NOT EXERCISED` no gate. Ver [`docs/dynamic-layer.md`](../docs/dynamic-layer.md).
- `.github/workflows/blindar.yml` — CI obrigatório
- `.husky/pre-commit + pre-push` — gates locais
- `.blindar/results/*.json` — output auditável + agregado
- `scripts/blindar/check-termination.sh` — decisão matemática de release

Doc completa: [`docs/deterministic-layer.md`](../docs/deterministic-layer.md).

## Intelligence System (⭐ v0.20)


Registry compartilhado de exceções/whitelist que TODOS os agentes
consultam pra evitar falso positivo. Vive em
`.blindar/intelligence.yml` no projeto-alvo.

Schema formal: [`schemas/intelligence.schema.json`](../schemas/intelligence.schema.json).

Por que existe: cada projeto tem casos legítimos onde uma "regra" não
aplica (ex: tabela `feature_flags` legitimamente não tem `tenant_id`).
Sem este registry, agentes geram ruído contínuo.

Cada agente declara sua seção. Exemplos:

```yaml
schema: blindar/intelligence@v1
mock-killer:
  ignore_paths: ["**/*.gen.ts", "**/__mocks__/**"]
db-architect:
  global_tables: [feature_flags, system_logs, migrations]
content-quality:
  protected_terms: ["Stripe", "WhatsApp", "MASTER"]
architect:
  router_mode: { auto_detect: true }
```

### Inline markers no código

Sem precisar editar YAML:

```ts
// @blindar:keep -- log intencional pra debug
console.warn('Falha de DB');

// @blindar:hardcode-ok -- código HTTP padrão
if (res.status === 429) backoff();
```

```sql
-- @blindar:global -- tabela legitimamente sem tenant_id
CREATE TABLE feature_flags ( ... );
```

### Learning mode

Quando ativado em `intelligence.yml`:

```yaml
global:
  learning_mode: true
```

Operador aprova override 1x interativamente → blindar grava em
`intelligence.yml` automaticamente. Próximas execuções respeitam sem
perguntar de novo.
