#!/usr/bin/env bash
# Wrapper API: fine-tune-data-leak — PII em training data + memorization risk
BLINDAR_AGENT="check-fine-tune-data-leak"
source "$(dirname "$0")/_lib.sh"
source "$(dirname "$0")/_api_wrapper.sh"

log_section "Check: fine-tune-data-leak (PII em training data via Claude API)"

# Detecta fine-tuning
FT_HIT=0
if command -v rg >/dev/null 2>&1; then
  if rg -l --type py --type ts --type js \
       "transformers.*Trainer|TrainingArguments|SFTTrainer|DPOTrainer|trl\.|peft\.|LoraConfig|fine_tuning|FineTune|client\.fine_tuning\.jobs|cohere.*finetune|co\.finetunes|aiplatform.*tuning|TuningJob|model_customization" \
       . >/dev/null 2>&1; then
    FT_HIT=1
  fi
fi

# Também detecta por arquivos .jsonl de training
JSONL_FILES=""
if [ "$FT_HIT" -eq 0 ]; then
  if command -v find >/dev/null 2>&1; then
    JSONL_FILES=$(find . -type f -name "*.jsonl" \
      \( -path "*train*" -o -path "*dataset*" -o -path "*finetune*" -o -path "*sft*" \) \
      ! -path "*/node_modules/*" ! -path "*/.git/*" 2>/dev/null | head -5)
    [ -n "$JSONL_FILES" ] && FT_HIT=1
  fi
fi

if [ "$FT_HIT" -eq 0 ]; then
  log_info "Nenhum código de fine-tuning ou training jsonl detectado — skipped"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

# Coleta evidência
EVIDENCE=""
EVIDENCE+="=== Fine-tune detection ===\nProjeto faz fine-tuning de modelo.\n\n"

[ -f "package.json" ] && EVIDENCE+="=== package.json ===\n$(head -c 2000 package.json)\n\n"
[ -f "pyproject.toml" ] && EVIDENCE+="=== pyproject.toml ===\n$(head -c 2000 pyproject.toml)\n\n"
[ -f "requirements.txt" ] && EVIDENCE+="=== requirements.txt ===\n$(head -c 2000 requirements.txt)\n\n"

if command -v rg >/dev/null 2>&1; then
  # Arquivos de training
  EVIDENCE+="=== Scripts de fine-tune ===\n"
  FT_FILES=$(rg -l --type py --type ts \
    "Trainer|SFTTrainer|TrainingArguments|peft|LoraConfig|fine_tuning|FineTune|finetunes|TuningJob" \
    . 2>/dev/null | head -6)
  for f in $FT_FILES; do
    EVIDENCE+="\n--- $f ---\n$(head -c 4000 "$f" 2>/dev/null)\n"
  done

  # Scrub / sanitize matches
  EVIDENCE+="\n=== Scrub / sanitize / Presidio matches ===\n"
  EVIDENCE+="$(rg -n --type py --type ts 'presidio|sanitize|scrub|anonymize|redact|\[CPF\]|\[EMAIL\]|\[PHONE\]' . 2>/dev/null | head -25)\n"

  # Dedup matches
  EVIDENCE+="\n=== Dedup matches ===\n"
  EVIDENCE+="$(rg -n --type py 'dedup|MinHash|datasketch|drop_duplicates|set\(.*hash' . 2>/dev/null | head -15)\n"

  # Split matches
  EVIDENCE+="\n=== Train/eval split matches ===\n"
  EVIDENCE+="$(rg -n --type py 'train_test_split|train_val_split|val_split|eval_split|group_split' . 2>/dev/null | head -15)\n"
fi

# Sample do training data (primeiras 100 linhas do primeiro .jsonl)
if [ -z "$JSONL_FILES" ] && command -v find >/dev/null 2>&1; then
  JSONL_FILES=$(find . -type f -name "*.jsonl" \
    ! -path "*/node_modules/*" ! -path "*/.git/*" 2>/dev/null | head -3)
fi

for jf in $JSONL_FILES; do
  if [ -f "$jf" ]; then
    EVIDENCE+="\n=== Training data sample: $jf (primeiras 100 linhas) ===\n"
    EVIDENCE+="$(head -100 "$jf" 2>/dev/null | head -c 15000)\n"
  fi
done

# Manifest / lineage
if command -v find >/dev/null 2>&1; then
  MANIFESTS=$(find . -type f \( -name "manifest.yml" -o -name "manifest.yaml" -o -name "dataset_card.md" -o -name "DATASET.md" \) \
    ! -path "*/node_modules/*" ! -path "*/.git/*" 2>/dev/null | head -5)
  for m in $MANIFESTS; do
    EVIDENCE+="\n=== $m ===\n$(head -c 2000 "$m" 2>/dev/null)\n"
  done
fi

# .gitignore (training data deve estar ignored)
[ -f ".gitignore" ] && EVIDENCE+="\n=== .gitignore (procure por .jsonl/datasets) ===\n$(head -c 2000 .gitignore)\n"

[ -f "${BLINDAR_DIR:-.blindar}/scan.json" ] && EVIDENCE+="\n=== Stack scan ===\n$(head -c 3000 ${BLINDAR_DIR:-.blindar}/scan.json)\n"

if [ -z "$EVIDENCE" ]; then
  log_warn "Sem evidência coletável"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

SYSTEM="Você é o agente fine-tune-data-leak do blindar.
Avalie risco de vazamento de dados em fine-tuning de modelo.

Critérios:
1. PII no training data: amostra de jsonl contém CPF, CNPJ, RG, email, telefone, CEP, cartão de crédito SEM scrub?
2. Padrões BR específicos: regex \d{3}\.?\d{3}\.?\d{3}-?\d{2} (CPF), \(?\d{2}\)?\s?9?\d{4}-?\d{4} (telefone)
3. Scrub pipeline: código usa Presidio ou regex próprio antes de jogar no Trainer?
4. Dedup: dataset deduplicated (exact + near via MinHash)? Duplicação amplifica memorization 10x.
5. Train/eval contamination: split por hash determinístico ou random? mesma example em train+val infla métrica.
6. Prompt:completion ratio: >1:50 indica recall factual → use RAG, não fine-tune (memorization quase certa)
7. Dataset manifest/lineage: versão, source, consent, checksum?
8. Training data commitado no git (CRIT se contém PII)
9. Extraction attack test pós-training?

Severities:
- crit: PII visível na amostra do training jsonl SEM scrub, training data commitado no git contendo PII
- high: sem dedup, sem scrub pipeline detectado, sem manifest
- med: split sem cuidado (random sem dedup-first), prompt:completion ratio alto sem RAG
- low: melhorias (extraction test, dataset card)

Reporte findings com arquivo/linha. Cite exemplos da amostra quando vir PII. Se zero amostra disponível, sev=low pedindo amostra."

blindar_api_check "$BLINDAR_AGENT" "$SYSTEM" "$EVIDENCE"
