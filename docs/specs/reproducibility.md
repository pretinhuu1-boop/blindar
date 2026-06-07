# Spec: Reproducibility check (item #16 do ROADMAP)

> Mesmo projeto rodado 2x deve produzir mesmo `sec.html` final. Hoje não.

## Problema

LLMs são não-determinísticas. Rodar `blindar` 2x no mesmo projeto
produz:
- Ordem diferente de ATKs descobertos
- IDs diferentes (ATK-001 num run, ATK-007 noutro)
- Implementações ligeiramente diferentes (variável `userId` vs `user_id`)
- Texto de PR diferente

Isso quebra: auditoria ("você refez e ficou diferente?"), comparação
("v0.5 vs v0.6 do skill, qual produziu melhor resultado?").

## Solução proposta

### Determinismo parcial via:

1. **ID determinístico de ATK**: hash da categoria+vector+file → ID
   estável. Mesmo bug detectado 2x recebe mesmo ID.

   ```
   ATK_ID = "ATK-" + sha256("{cat}|{file}|{line_range}|{vector_signature}")[:8]
   ```

2. **Ordenação canônica** de inventory/threats/atks por chave
   (id ASC, severity DESC, file path).

3. **Templates fixos** pra PR titles/messages. Variáveis preenchidas
   sempre na mesma ordem.

4. **Seed do LLM** quando suportado (Claude tem `temperature: 0`,
   OpenAI tem `seed: int`).

5. **Skip de campos voláteis** no hash de comparação:
   - timestamps (`last_updated`, `covered_at`)
   - PR numbers (ordem de mergeio depende de GH)
   - hashes de commit

## Verificação

Script `scripts/reproducibility-check.ps1`:

```powershell
# Roda blindar em fork limpo, captura sec.html final
git clone $project /tmp/run1
cd /tmp/run1 && blindar
sec1 = canonical_hash(sec.html)

git clone $project /tmp/run2
cd /tmp/run2 && blindar
sec2 = canonical_hash(sec.html)

if (sec1 -eq sec2) {
    Write-Host "REPRODUCIBLE"
} else {
    Write-Host "DIVERGENT — analyze diff"
    diff /tmp/run1/sec.html /tmp/run2/sec.html
}
```

`canonical_hash` ignora timestamps, PR numbers, commit shas — só
estrutura semântica.

## Limitações honestas

- **100% reproducibility é impossível** com LLM. Aceitar drift dentro
  de um budget (ex: ≥95% match estrutural).
- **Lógica de negócio**: AI pode escolher implementações funcionalmente
  equivalentes mas diferentes (uso de `Option<T>` vs `null` em Rust,
  por exemplo). Ambas corretas; comparação precisa abstrair.
- **Seed do LLM só vale na mesma versão do modelo**. GPT-4 hoje ≠
  GPT-4 em 6 meses.

## Por que não está implementado

1. Requer **decisão de schema canônico** — qual versão do sec.html é
   "ground truth"? Migration matters.
2. ID determinístico precisa de **hash function estável** no contrato
   do agent — refactor de prompt.
3. Reproducibility só agrega valor se time **realmente comparar runs**.
   Sem caso de uso real, é over-engineering.

## Quando faz sentido implementar

- Comparação entre versões do skill (regression testing do skill)
- Auditoria que pede "mostre que isso é replicável"
- Pesquisa acadêmica sobre AI-assisted hardening
