---
name: sbom-slsa
category: supply-chain
module: 5
priority: P1
description: |
  Software Bill of Materials (SBOM) em CycloneDX/SPDX a cada build,
  SLSA build provenance níveis 1-3, signing de artefatos via Sigstore
  (Cosign) + Rekor transparency log. Regulação 2026 crescente (UE AI
  Act, US Executive Order 14028, NIST SSDF) exige isso pra B2B
  enterprise e governo. Sem isso, fica fora de licitação federal.
---

# Agent: sbom-slsa

## Missão

2026 mudou: governo dos EUA exige SBOM em fornecedor federal. UE AI Act
exige provenance. Cliente enterprise B2B começa a pedir em RFP. Quem não
tem, perde contrato. Este agente prescreve a stack mínima pra estar
em conformidade.

## Quando rodar

- Módulo 5 selecionado
- Rigor: `production` ou `compliance`
- Operador pediu "SBOM", "SLSA", "supply chain compliance", "RFP federal"

## A. SBOM (Software Bill of Materials)

Lista TODOS componentes que entram no produto: bibliotecas, versões,
licenças, hashes.

### Geração em CI

```yaml
# .github/workflows/sbom.yml
- name: Generate SBOM (CycloneDX)
  run: npx @cyclonedx/cyclonedx-npm --output-file sbom.cdx.json

- name: Generate SBOM (SPDX, alternativa)
  uses: anchore/sbom-action@v0
  with: { format: spdx-json, output-file: sbom.spdx.json }

- name: Upload as release artifact
  uses: softprops/action-gh-release@v2
  with: { files: sbom.cdx.json }
```

Pra Python: `cyclonedx-py`. Pra Go: `cyclonedx-gomod`. Pra container:
`syft`.

### Inclui

- Direct deps + transitivas
- Versão exata (pinada)
- Hash SHA-256
- Licença (MIT, Apache-2.0, etc.)
- Link pra source
- CVEs conhecidos (cross-ref com OSV)

### Análise de vulnerabilidade contra SBOM

```bash
grype sbom:./sbom.cdx.json --fail-on high
# OU
trivy sbom ./sbom.cdx.json --severity HIGH,CRITICAL --exit-code 1
```

CI vermelha se HIGH/CRIT detectado. Manual override exige `accept-risk`.

## B. SLSA (Supply-chain Levels for Software Artifacts)

Atesta **como** o artefato foi construído. 4 níveis.

| Nível | O que prova |
|---|---|
| **SLSA 1** | Build process documentado, provenance gerado |
| **SLSA 2** | Build em CI com hosted runner, source versionado, autenticado |
| **SLSA 3** | Build isolado, source + build platform verificados, provenance assinado |
| **SLSA 4** | Two-party review, hermetic builds, reproducible |

**Meta realista 2026**: SLSA 3.

### Provenance em GitHub Actions

```yaml
- name: Generate provenance
  uses: slsa-framework/slsa-github-generator/.github/workflows/generator_generic_slsa3.yml@v2
  with:
    base64-subjects: "${{ steps.hash.outputs.subjects }}"
    upload-assets: true
```

Gera arquivo `*.intoto.jsonl` que prova: quem buildou, quando, de qual
commit, com qual workflow.

## C. Signing (Sigstore / Cosign)

```bash
# Assinar imagem Docker
cosign sign --yes ghcr.io/owner/app:v1.2.3

# Assinar binário/arquivo
cosign sign-blob --yes --bundle release.bundle release.tar.gz

# Verificar antes de deploy
cosign verify \
  --certificate-identity-regexp '^https://github.com/owner/' \
  --certificate-oidc-issuer 'https://token.actions.githubusercontent.com' \
  ghcr.io/owner/app:v1.2.3
```

### Rekor (transparency log)

Toda assinatura vai automaticamente pra Rekor (`rekor.sigstore.dev`),
log público append-only. Você pode provar "essa versão saiu deste
commit" 5 anos depois sem precisar guardar chaves.

## D. Política de admissão (cluster K8s)

```yaml
# Kyverno / OPA Gatekeeper
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata: { name: verify-signed-images }
spec:
  validationFailureAction: enforce
  rules:
    - name: verify-cosign-signature
      match: { resources: { kinds: [Pod] } }
      verifyImages:
        - imageReferences: ['ghcr.io/owner/*']
          attestors:
            - keyless:
                rekor: { url: 'https://rekor.sigstore.dev' }
                subject: 'https://github.com/owner/'
                issuer: 'https://token.actions.githubusercontent.com'
```

Cluster recusa rodar imagem sem assinatura válida.

## E. Reproducible builds

Mesmo source = mesmo binary. Permite verificar "esse artefato bate com
esse commit". Difícil mas crescente.

Práticas:
- Timestamps fixos (`SOURCE_DATE_EPOCH`)
- Sem `random` no build
- Sem `Date.now()` em embeds
- Lockfile commitado (yarn.lock / pnpm-lock.yaml / Pipfile.lock)
- Docker base image pinada por SHA (não `:latest`)

## F. Distribuição com SBOM anexo

```bash
# Anexar SBOM ao release
gh release create v1.2.3 \
  dist/app.tar.gz \
  sbom.cdx.json \
  sbom.cdx.json.sig \
  provenance.intoto.jsonl
```

Cliente baixa, valida assinatura, lê SBOM antes de instalar.

## G. Conformidade regulatória 2026

| Regulação | Exige |
|---|---|
| **US Executive Order 14028** | SBOM em fornecedor federal |
| **NIST SSDF (SP 800-218)** | Práticas de secure development |
| **UE Cyber Resilience Act** (CRA, 2027) | SBOM + provenance pra produtos com componentes digitais |
| **UE AI Act** | Provenance em modelos de IA |
| **DORA** (UE financeiro) | Supply chain risk monitoring |
| **PCI DSS v4** | Inventário de software |

## H. Greps

```bash
# Lockfile faltando
test -f package-lock.json || test -f yarn.lock || test -f pnpm-lock.yaml || echo "FAIL: sem lockfile"

# Base image sem SHA pin
rg -n "FROM [a-z]+:(latest|\d+\.\d+)" Dockerfile* | rg -v "@sha256:"

# Build com Date.now() ou Math.random() (anti-reprodutível)
rg -n "Date\.now\(\)|Math\.random\(\)" --type ts -g 'build*' -g 'scripts/build*'

# Action sem SHA-pin (usa tag, pode mudar)
rg -nU "uses: [^@]+@v?\d" .github/workflows/
```

## Output em sec.html

```
┌─ SBOM + SLSA (Módulo 5) ─────────────────────────────────┐
│ SBOM CycloneDX gerado          : ✅ a cada build         │
│ SBOM SPDX (formato alternativo): ✅                       │
│ Componentes catalogados        : 1.247                   │
│ Licenças identificadas         : 38 distintas            │
│ CVEs HIGH+CRIT no SBOM         : 0 ✅                    │
│ SLSA level atingido            : 3                        │
│ Provenance gerado (in-toto)    : ✅                       │
│ Sigstore signing (Cosign)      : ✅                       │
│ Rekor transparency log         : ✅                       │
│ K8s admission policy           : ✅ Kyverno enforce       │
│ Reproducible build             : ⚠ trabalhando           │
│ Lockfile pinado                : ✅                       │
│ Base images SHA-pinned         : ✅ 8/8                   │
│ GH Actions SHA-pinned          : ✅ 23/23                 │
│ Status                         : ✅ COMPLIANT 2026       │
└───────────────────────────────────────────────────────────┘
```

## Anti-padrões

- ❌ Sem SBOM em release (RFP enterprise: descartado)
- ❌ Action usando tag (`@v4`) em vez de SHA (`@a1b2c3...`)
- ❌ Base image `:latest` (não-reprodutível, vulnerável)
- ❌ SBOM gerado uma vez e esquecido (precisa ser a cada release)
- ❌ Não assinar artefato (qualquer um substitui)
- ❌ Não verificar assinatura antes de deploy
- ❌ Skipar SLSA "porque é difícil" (perde contrato)
- ❌ Lockfile no `.gitignore` (build não-determinístico)
- ❌ Build com `RANDOM_SEED` aleatório (não-reprodutível)
- ❌ Sem política de admissão no cluster (kubectl roda qualquer coisa)
- ❌ SBOM com falsos positivos não-acionados (vira ruído)
