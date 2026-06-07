# docs/specs/ — especificações pendentes de implementação

Cada arquivo aqui é uma **spec** — define o formato/contrato/comportamento
de algo que **ainda não tem implementação completa no skill**.

⚠ **Por que existe esta pasta**: o skill segue o princípio "nada entra
sem bug real observado". Specs aqui são desenhos prontos pra quando
chegar a dor real OU pra contribuidores externos implementarem.

## Spec docs

| Spec | Item do ROADMAP | Status |
|---|---|---|
| [`evidence-package.md`](evidence-package.md) | #15 | spec pronta, falta CLI gerador |
| [`atk-sbom.md`](atk-sbom.md) | #17 | spec pronta, falta integração com Fase 6 |
| [`reproducibility.md`](reproducibility.md) | #16 | spec pronta, requer determinismo na seed |
| [`load-test-harness.md`](load-test-harness.md) | #6 | spec pronta, falta integração com Fase 5 |
| [`notifications.md`](notifications.md) | #24 | spec pronta, falta hook nas fases |
| [`api-contract.md`](api-contract.md) | #3 | spec pronta, falta agent dedicado |
| [`race-fuzzing.md`](race-fuzzing.md) | #4 | spec pronta, falta harness real |

## Como usar uma spec

1. Ler o doc — entende o problema e a forma da solução
2. Verificar se o problema é real no seu projeto
3. Implementar (ou abrir issue/PR no repo do skill)
4. Quando implementação landa, doc sai de `specs/` e vira parte de
   `pipeline/` ou `agents/`

## Como contribuir spec → implementação

Princípios do skill aplicam:

- Implementação ≤ 80 LOC por PR (quebre em N rounds se grande)
- Teste real (≥ 3 asserts) cobrindo happy + edge + attack
- Atualizar ROADMAP.md movendo item de "🔜 spec" pra "✅ implementado"
- CHANGELOG.md ganha entrada da versão
