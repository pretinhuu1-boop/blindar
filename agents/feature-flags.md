---
name: feature-flags
category: devops
module: 14
priority: P1
description: |
  Sistema de feature flags estruturado: rollout gradual (%), kill switch
  (desliga feature em prod em 5s), A/B testing, flags por tenant/role/
  região, cleanup obrigatório de flags estáveis (não deixar flag morto
  virar dívida). Tabela `feature_flags` no DB OU serviço dedicado
  (LaunchDarkly/GrowthBook/Unleash).
---

# Agent: feature-flags

## Missão

Deploy contínuo sem feature flags é Russian roulette. Com flags, você
separa **deploy** (código em produção) de **release** (feature visível ao
user). Bug em prod? Desliga em 5s sem rollback de deploy.

## Quando rodar

- Módulo 14 selecionado
- Operador pediu "feature flag", "rollout gradual", "kill switch", "A/B test"
- Time > 2 devs (coordenação fica viável com flags)

## A. Ciclo de vida de uma flag

```
┌─────────┐     ┌────────┐     ┌────────┐     ┌────────┐     ┌──────────┐
│ created │ --> │ dev    │ --> │ rollout│ --> │ stable │ --> │ removed  │
└─────────┘     └────────┘     │ 10/50% │     │  100%  │     │ (deleted)│
                               └────────┘     └────────┘     └──────────┘
                                                  │
                                                  ↓
                                          OBRIGATÓRIO remover
                                          (não deixar dívida)
```

**Flag estável > 30 dias** = código sempre passa por ela = vira dívida.
Cleanup obrigatório.

## B. Tipos de flag

| Tipo | Tempo de vida | Exemplo |
|---|---|---|
| **Release flag** | Temporário (semanas) | Nova feature em rollout gradual |
| **Ops flag (kill switch)** | Permanente | Desliga integração externa em emergência |
| **Experiment flag** | Temporário (4-8 semanas) | A/B test de copy ou design |
| **Permission flag** | Permanente | Feature só pra plano Pro |

## C. Storage

### Opção 1: Tabela própria (default pra projetos pequenos/médios)

```sql
CREATE TABLE feature_flags (
  key             TEXT PRIMARY KEY,
  description     TEXT NOT NULL,
  type            TEXT NOT NULL CHECK (type IN ('release','ops','experiment','permission')),
  enabled         BOOLEAN NOT NULL DEFAULT false,
  rollout_pct     SMALLINT NOT NULL DEFAULT 0 CHECK (rollout_pct BETWEEN 0 AND 100),
  enabled_tenants UUID[],
  disabled_tenants UUID[],
  enabled_roles   TEXT[],
  enabled_users   UUID[],          -- beta testers
  variations      JSONB,            -- A/B: {"control": 0.5, "v1": 0.5}
  owner           TEXT NOT NULL,    -- quem criou (responsável)
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at      TIMESTAMPTZ,      -- alerta se passar e não foi removido
  removed_at      TIMESTAMPTZ
);

CREATE INDEX idx_ff_active ON feature_flags(key) WHERE removed_at IS NULL;
```

### Opção 2: Serviço dedicado (50+ flags ou alta cadência)

- **GrowthBook** (open source, self-hosted) — recomendado
- **Unleash** (open source, mais complexo)
- **Flagsmith** (open source, hosted opção)
- **LaunchDarkly** (SaaS, caro, enterprise)

## D. Evaluação no backend (não confiar no client)

```ts
async function isEnabled(key: string, ctx: { userId, tenantId, role }) {
  const flag = await db.featureFlag.findUnique({ where: { key, removed_at: null } });
  if (!flag) return false;
  if (!flag.enabled) return false;

  // Override por user (beta testers sempre veem)
  if (flag.enabled_users?.includes(ctx.userId)) return true;
  if (flag.disabled_tenants?.includes(ctx.tenantId)) return false;
  if (flag.enabled_tenants?.includes(ctx.tenantId)) return true;
  if (flag.enabled_roles?.length && !flag.enabled_roles.includes(ctx.role)) return false;

  // Rollout gradual — hash consistente do userId
  if (flag.rollout_pct < 100) {
    const hash = murmurhash(ctx.userId + key) % 100;
    return hash < flag.rollout_pct;
  }
  return true;
}
```

**Importante:** mesmo user sempre cai no mesmo bucket (hash determinístico).
Senão A/B test não funciona — user vê variação A num refresh, B no outro.

## E. Cliente consome resultado, não avalia

```ts
// Frontend pede ao backend "quais flags estão ON pra mim?"
const flags = await fetch('/api/me/feature-flags').then(r => r.json());
// { 'new-checkout': true, 'dark-mode-v2': false }

// Componente
{flags['new-checkout'] ? <CheckoutV2 /> : <CheckoutV1 />}
```

NUNCA enviar **todas** as flags pro client (vaza roadmap). Filtrar por
relevância ao user.

## F. Greps anti-pattern

```bash
# Feature flag inline em código (deveria estar no sistema de flags)
rg -n "if\s*\(\s*process\.env\.[A-Z_]*FEATURE" --type ts
rg -n "if\s*\(\s*process\.env\.[A-Z_]*ENABLE" --type ts
rg -n "isTesting|isNewVersion|isV2" --type ts -g '!*.test.*'

# Comentário "// TEMP: remover depois" (dívida garantida)
rg -ni "(temp|temporary|remove later|remover depois).*flag" --type ts
```

## G. A/B testing (variations)

```ts
const variant = useExperiment('checkout-redesign', {
  variations: ['control', 'v1', 'v2'],
  defaultVariant: 'control'
});

// Backend retorna variation baseado em hash determinístico
{variant === 'v1' && <CheckoutV1 />}
{variant === 'v2' && <CheckoutV2 />}
{variant === 'control' && <CheckoutOriginal />}

// Track exposure para análise
useEffect(() => {
  analytics.track('experiment_exposure', { experiment: 'checkout-redesign', variant });
}, [variant]);
```

## H. Kill switch (emergência)

```
Cenário: integração com gateway pagamento começou a falhar em 100% das tx.

1. Acesso ao admin do feature-flags (ou query SQL direta)
2. UPDATE feature_flags SET enabled = false WHERE key = 'payment-gateway-x'
3. Backend deixa de chamar gateway X em segundos
4. Fallback pro gateway Y ativado por outra flag
5. Hotfix com calma, sem perder vendas
```

**Latência de propagação** do flag → backend: ≤ 30s
(cache TTL 30s ou pub/sub Redis em sistemas grandes).

## I. Audit log de mudanças em flags

```sql
CREATE TABLE feature_flag_changes (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid_v7(),
  flag_key    TEXT NOT NULL,
  changed_by  UUID NOT NULL,
  field       TEXT NOT NULL,       -- 'enabled', 'rollout_pct', etc
  old_value   JSONB,
  new_value   JSONB,
  reason      TEXT,                -- opcional, justifica
  at          TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

Pra investigar "quem desligou X e por quê" depois.

## J. Cleanup obrigatório

### Detecção em CI

```bash
# Script que detecta flags estáveis > 30 dias com rollout 100%
SELECT key, owner, age(now(), created_at) as age
FROM feature_flags
WHERE rollout_pct = 100 AND enabled = true
  AND removed_at IS NULL
  AND created_at < now() - interval '30 days';
```

Resultado vira issue automática no GitHub → owner deve remover flag + branches.

### Remoção segura (3 passos)

1. **Marcar `removed_at`** no DB (flag para de existir, código resolve pro
   path default — o que era ON)
2. **Remover branches/ifs** no código (deleta `if (flag) { else }`)
3. **Drop row** após 7 dias de observação

## Output esperado em sec.html

```
┌─ Feature Flags (Módulo 14) ──────────────────────────────┐
│ Storage                       : tabela DB ✅              │
│ Flags ativas                  : 12 (8 release, 3 ops, 1 exp)│
│ Flags estáveis > 30d          : 0 ✅ (alertava 2)         │
│ Evaluation no backend         : ✅                         │
│ Hash determinístico           : ✅                         │
│ Audit log                     : ✅                         │
│ Kill switch latência          : 22s (meta < 30s) ✅       │
│ A/B test infra                : ✅ 1 experimento ativo    │
│ Status                        : ✅ MANAGED                │
└───────────────────────────────────────────────────────────┘
```

## Anti-padrões

- ❌ `if (process.env.NEW_FEATURE)` (sem rollback runtime)
- ❌ Avaliar flag no client (vaza roadmap + bypass fácil)
- ❌ Hash não-determinístico (user vê variação trocando)
- ❌ Flag sem `owner` e `expires_at`
- ❌ Flag estável > 30 dias virando código permanente sem cleanup
- ❌ Kill switch que demora 5min pra propagar
- ❌ A/B test sem track de `experiment_exposure`
- ❌ Enviar todas as flags pro client
- ❌ Modificar flag sem audit log
