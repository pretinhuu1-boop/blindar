# Fase 8 — Drift detection (subfase de maintenance)

Detecta se defesas implementadas em ciclos anteriores foram **removidas**
ou **enfraquecidas** em PRs subsequentes (não-blindar).

⚠ **Status v0.6.0**: subfase opcional de [`07-maintenance.md`](07-maintenance.md).

## Sinais de drift

### 1. Grep estático removido ou bypassado

Cada round da Fase 3 implementa um grep que falha se a defesa regride.
Drift = grep deletado ou ignorado.

**Detecção**:
```bash
# Lista grep guards históricos
git log --all --diff-filter=A --name-only | grep -E "scripts/grep-guard-" | sort -u

# Compara com o que existe hoje
for g in $(history list); do
  [ -f "$g" ] || echo "MISSING: $g"
done
```

### 2. Teste anti-regressão `test_red{XXX}.py` deletado

Cada round adiciona um teste. Se some, drift.

**Detecção**: `git log --all --diff-filter=D --name-only | grep test_red`

### 3. Header de segurança removido em middleware

CSP, HSTS, X-Content-Type-Options — se sumiram do middleware central,
drift.

**Detecção**: smoke test de header em endpoint conhecido
```bash
curl -sI https://staging.app/api/me | grep -iE 'strict-transport-security|content-security-policy|x-frame-options'
```

### 4. Rate-limit reduzido ou removido

Config de rate-limit no proxy/app foi tunado pra mais permissivo.

**Detecção**: comparar config atual vs snapshot guardado no
`.blindar/checkpoints/`.

### 5. Audit chain interrompida

Hash chain do compliance/audit log — se hash quebra, alguém modificou
retroativamente OU código que escreve foi alterado.

**Detecção**: `verify_chain()` test no CI. Falha = drift.

### 6. Dependência crítica downgraded

Lib de auth/crypto teve versão reduzida (raro mas acontece).

**Detecção**: compara lockfile current vs último checkpoint.

### 7. Config de produção com flag de debug

`.env.production` ou config IaC ganhou flag que skill bloqueava.

**Detecção**: grep contra `.blindar/checkpoints/<last>/forbidden_flags.txt`.

## Algoritmo

```
1. Carregar último checkpoint válido: .blindar/checkpoints/<latest>.json
2. Pra cada categoria de sinal acima:
   a. Executar detection
   b. Comparar com expected do checkpoint
   c. Se diverge: adicionar a drift_findings[]
3. Se drift_findings vazio: nenhum drift, retornar
4. Senão: criar issue/PR pra cada drift
   - Severity = severity original do ATK que era coberto
   - Sugestão: revert do change que removeu OU re-implementar defesa
```

## Output

`.blindar/checkpoints/drift-YYYY-MM-DD.json`:

```json
{
  "detected_at": "2026-09-01T10:00:00Z",
  "drift_findings": [
    {
      "type": "grep_guard_removed",
      "guard": "scripts/grep-guard-csp.sh",
      "atk": "ATK-007",
      "removed_in_commit": "abc1234",
      "severity": "high",
      "suggested_action": "revert or re-implement guard"
    }
  ],
  "total": 1
}
```

## PR de remediação

Skill abre 1 PR por drift finding:

```
title: sec(drift): restore <defesa> removed in <commit>

body:
ATK-007 was previously covered by <test/grep>. Removed in <commit>.
Restoring with optional refactor if original defense outdated.
```

## Ver também

- [`pipeline/07-maintenance.md`](07-maintenance.md) — orquestrador
- [`docs/specs/reproducibility.md`](../docs/specs/reproducibility.md) —
  por que checkpoints servem como ground truth

## Limitações honestas

- **Detecta drift de defesa documentada**. Defesa que nunca passou
  pelo skill é invisível.
- **False positives possíveis** se refactor legítimo move guard pra
  outro arquivo. Operador revisa o PR.
- **Não detecta drift de qualidade** (perf ficou pior, etc.). Foco é
  segurança.
