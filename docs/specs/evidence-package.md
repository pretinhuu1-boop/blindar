# Spec: Evidence Package (item #15 do ROADMAP)

> Pacote auditável assinado contendo prova do que o blindar fez num
> projeto. Pra auditoria, certificação, compliance.

## Problema

Hoje, ao terminar Fase 6, o output é "N PRs + sec.html + 3 runbooks".
Verificar isso DEPOIS exige acesso ao repo + paciência. Auditor externo
precisa de **artifact único, autocontido, verificável**.

## Solução proposta

Ao final da Fase 6, gerar `blindar-evidence-vX.Y.Z.tar.gz` contendo:

```
blindar-evidence-{project}-{date}.tar.gz
├── manifest.json           ← índice + hashes + assinatura
├── sec.html                ← snapshot final do dashboard
├── state.json              ← estado final
├── prs.json                ← lista de PRs mergeados com diffs
├── tests-added.json        ← lista de testes adicionados (path + assertions count)
├── guards.json             ← grep estáticos adicionados
├── runbooks/               ← cópia dos docs gerados
├── coverage-{framework}.json  ← coverage por framework alvo
└── signature.sig           ← cosign signature de manifest.json
```

### Manifest schema (futuro `schemas/evidence.schema.json`)

```json
{
  "blindar_version": "0.5.0",
  "project": "owner/repo",
  "generated_at": "2026-09-01T15:00:00Z",
  "ciclo": {
    "started_at": "2026-08-15T09:00:00Z",
    "ended_at": "2026-09-01T14:55:00Z",
    "rounds_total": 47,
    "adversarial_rounds": 5
  },
  "results": {
    "atks_total": 68,
    "atks_covered": 65,
    "atks_partial": 2,
    "atks_accepted_risk": 1,
    "tests_added": 102,
    "guards_added": 47,
    "loc_changed": 3214
  },
  "frameworks": [
    { "name": "asvs-l2", "coverage_pct": 91 },
    { "name": "iso27001-A.8", "coverage_pct": 88 }
  ],
  "hashes": {
    "sec.html": "sha256:...",
    "state.json": "sha256:..."
  }
}
```

## Implementação proposta

```powershell
# scripts/evidence.ps1 (a criar)
blindar-evidence --output blindar-evidence.tar.gz
```

Lógica:
1. Coletar `sec.html`, `.blindar/state.json`
2. `gh pr list --state merged --search "label:blindar"` → lista PRs
3. Pra cada PR: `gh pr diff <n>` → tamanho + arquivos tocados
4. Achar `tests/test_red*.py` e contar assertions por arquivo
5. Achar grep guards (convention: `scripts/grep-guard-*.sh`)
6. Calcular coverage pct por framework alvo
7. Empacotar tar.gz
8. Assinar com cosign (`cosign sign-blob`) se chave configurada

## Verificação por terceiros

```bash
# Auditor recebe blindar-evidence.tar.gz + public key
cosign verify-blob --key blindar.pub --signature signature.sig manifest.json
tar xzf blindar-evidence.tar.gz
# Abre sec.html, lê manifest, verifica hashes
```

## Por que não está implementado

1. Requer **decisão de key management**: chave do dono do projeto? Da
   org? Da plataforma? Cada opção tem implicações.
2. Cosign é dep nova — preferi não introduzir sem decisão.
3. Coverage por framework precisa do **multi-framework target**
   (item #18) implementado primeiro.

## Quando faz sentido implementar

- Time persegue certificação formal (ISO 27001, SOC 2 Type II)
- Auditor pede artifact verificável
- Mais de 3 projetos rodando blindar — vira repetição manual

## Mapeamento de frameworks

- ISO 27001 A.12.1.2 (Change management evidence)
- NIST SP 800-53 AU-12 (Audit generation)
- SOC 2 CC8.1 (change management documentation)
