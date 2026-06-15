---
name: mlops
category: ai
module: 2
priority: P2
description: |
  Quem treina modelo próprio (não LLM API): training pipeline com
  reprodutibilidade (DVC/MLflow), model registry versionado, A/B rollout
  de modelos (shadow → canary → full), drift detection (input + concept),
  feature store, GPU cost controls, dataset lineage. Cobre OWASP ML Top 10.
---

# Agent: mlops

## Missão

Modelo próprio em prod sem MLOps = "deu accuracy 95% na minha máquina"
+ "modelo virou crap em 6 meses ninguém viu". Este agente prescreve
training reprodutível + monitoring contínuo.

## Quando rodar

- Módulo 2 selecionado
- Detectado: `mlflow`, `dvc`, `kubeflow`, `sagemaker`, `vertex-ai`,
  scripts de training/inference
- Operador pediu "modelo próprio", "ML pipeline", "MLOps"

## A. Reprodutibilidade

```
Training run X em data Y com hyperparams Z → modelo M
Mesmo X+Y+Z = mesmo M (a menos de variação de hardware)
```

Ferramentas:
- **DVC** — versiona datasets + modelos no git (LFS-style)
- **MLflow** — tracking de runs, params, métricas, artefatos
- **Weights & Biases** — alternativa hosted
- **Hydra** — config-as-code pra hyperparams

```python
mlflow.start_run()
mlflow.log_params({'lr': 0.001, 'batch_size': 32, 'epochs': 10})
mlflow.log_metrics({'val_acc': 0.93, 'val_loss': 0.21})
mlflow.log_artifact('model.pt')
mlflow.end_run()
```

## B. Model registry

```python
# Registrar versão
mlflow.register_model('runs:/abc123/model', 'salon-classifier')

# Promover stage
client.transition_model_version_stage(
    name='salon-classifier', version=5, stage='Production'
)
```

Stages: `None → Staging → Production → Archived`.

## C. Rollout (shadow → canary → full)

```python
# Shadow: roda em paralelo, NÃO afeta user
def predict(input):
    real_pred = production_model.predict(input)
    shadow_pred = candidate_model.predict(input)
    log_comparison(real_pred, shadow_pred)  # análise offline
    return real_pred

# Canary: 10% dos requests
if hash(user_id) % 100 < 10:
    return candidate_model.predict(input)
return production_model.predict(input)
```

## D. Drift detection

| Tipo | O que monitora |
|---|---|
| **Data drift** (input) | Distribuição das features muda (ex: novos usuários diferentes) |
| **Concept drift** (target) | Relação input→output mudou (ex: COVID mudou comportamento) |
| **Prediction drift** | Distribuição das predições muda |

Lib: `evidently`, `nannyml`, `whylogs`.

Alertar quando drift > threshold → triggera retraining.

## E. Feature store

Centraliza features (cálculos derivados) entre training e inference:

- **Feast** (open source)
- **Tecton** (managed)

Garante: feature usada em training é a MESMA usada em inference (anti
"training-serving skew").

## F. Cost controls

```python
# GPU autoscale com cap
# Não deixar treinar > N horas sem aprovação
# Spot instances pra training (interruptible)
# Pre-emptible workers
```

Cron mata jobs > 24h sem progresso.

## G. Dataset lineage

```yaml
dataset:
  name: appointments-2026-q2
  version: v3
  source: prod_db.appointments WHERE created_at BETWEEN ...
  derived_from: appointments-2026-q1.v2
  pii_redacted: true
  bias_audit: docs/bias-audit-q2.md
```

Saber **de onde** veio o dado é compliance + reprodutibilidade.

## H. OWASP ML Top 10 (highlights)

- **ML01 Input manipulation** — adversarial examples → input validation
- **ML02 Data poisoning** — dataset signed, controlado quem contribui
- **ML03 Model inversion** — diff privacy, limit query rate
- **ML04 Membership inference** — não retornar confidence demais
- **ML05 Model stealing** — rate limit, WAF, watermarking
- **ML10 Supply chain** — modelos baixados de HuggingFace sem verify

## I. Greps

```bash
# Modelo carregado sem version pinning
rg -n "load_model|from_pretrained" --type py | rg -v "version|revision"

# Training sem seed
rg -n "torch\.manual_seed|np\.random\.seed|random\.seed" --type py
# (deve ter — se grep não retorna NADA, não tem)

# Inference sem timeout
rg -n "model\.predict|\.forward" --type py -B 5 | rg -v "timeout"
```

## Output em sec.html

```
┌─ MLOps (Módulo 2) ───────────────────────────────────────┐
│ Tracking (MLflow)             : ✅                        │
│ Model registry com stages     : ✅ Staging/Prod          │
│ Reprodutibilidade (seed)      : ✅                        │
│ Rollout shadow + canary       : ✅ 10% canary             │
│ Drift detection (evidently)   : ✅ data + concept        │
│ Feature store (Feast)         : ✅                        │
│ Dataset lineage versionado    : ✅ DVC                    │
│ PII redacted em training data : ✅                        │
│ Bias audit                    : ✅ trimestral             │
│ GPU autoscale + cap           : ✅ max 4 GPUs             │
│ OWASP ML Top 10 cobertos      : 8/10                      │
│ Status                        : ✅ ML-PROD-READY         │
└───────────────────────────────────────────────────────────┘
```

## Anti-padrões

- ❌ Notebook Jupyter em produção sem versionamento
- ❌ Dataset em CSV no Drive, sem lineage
- ❌ Modelo direto pra prod sem shadow/canary
- ❌ Sem drift detection (modelo apodrece silencioso)
- ❌ Re-train mensal "porque sim" (sem trigger por drift)
- ❌ HuggingFace model sem verify checksum
- ❌ Training sem seed (não-reprodutível)
- ❌ Feature computada diferente em train vs inference
- ❌ Inference sem timeout (modelo trava)
- ❌ Dataset com PII sem redact
- ❌ Sem rate limit em endpoint de predict (model stealing)
