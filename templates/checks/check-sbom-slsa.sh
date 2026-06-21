#!/usr/bin/env bash
# Materializa agente: sbom-slsa
# SBOM gerado em CI, SLSA provenance, Cosign signing, GH Actions SHA-pinned

BLINDAR_AGENT="check-sbom-slsa"
source "$(dirname "$0")/_lib.sh"

log_section "Check: SBOM + SLSA + Cosign"

FAIL=0

# 1. Lockfile presente (reproducible builds)
log_info "Verificando lockfile..."
if is_nodejs; then
  if [ ! -f "package-lock.json" ] && [ ! -f "yarn.lock" ] && [ ! -f "pnpm-lock.yaml" ]; then
    add_finding "high" "Sem lockfile (package-lock/yarn.lock/pnpm-lock) — build não-determinístico" "" ""
    log_fail "Lockfile ausente"
    FAIL=1
  fi
fi

# 2. Base image SHA-pinned (Dockerfile)
if [ -f "Dockerfile" ]; then
  log_info "Verificando FROM com SHA pin..."
  UNPIN=$(grep -cE "^FROM [^@]+:[^@]+$" Dockerfile 2>/dev/null || echo 0)
  if [ "$UNPIN" -gt 0 ]; then
    add_finding "high" "$UNPIN FROM em Dockerfile sem @sha256: (não-reprodutível, vulnerável)" "Dockerfile" ""
  fi

  # FROM :latest é CRIT
  LATEST=$(grep -c ":latest$" Dockerfile 2>/dev/null || echo 0)
  if [ "$LATEST" -gt 0 ]; then
    add_finding "crit" "FROM com :latest em Dockerfile — vulnerabilidade garantida com tempo" "Dockerfile" ""
    FAIL=1
  fi
fi

# 3. GH Actions com SHA pin (não tag mutável)
if [ -d ".github/workflows" ]; then
  log_info "Verificando uses: SHA-pinned..."
  TMP=$(mktemp)
  rg -nE "uses: [^@]+@v?\d+" .github/workflows/ 2>/dev/null > "$TMP" || true
  ACTION_UNPIN=$(wc -l < "$TMP" || echo 0)
  if [ "$ACTION_UNPIN" -gt 0 ]; then
    add_finding "high" "$ACTION_UNPIN GitHub Action(s) usando tag em vez de SHA — supply chain risk" ".github/workflows/" ""
    log_warn "$ACTION_UNPIN actions sem SHA pin"
  fi
  rm -f "$TMP"
fi

# 4. SBOM workflow ativo
log_info "Verificando geração de SBOM..."
HAS_SBOM=$(grep -lrE "(cyclonedx|@cyclonedx|spdx-tools|anchore/sbom-action|syft)" .github/workflows/ 2>/dev/null | head -1)
if [ -z "$HAS_SBOM" ]; then
  add_finding "med" "Sem geração de SBOM em CI — RFP federal exige" ".github/workflows/" ""
fi

# 5. SLSA provenance
HAS_PROVENANCE=$(grep -lrE "(slsa-framework|in-toto|attestations:|sigstore)" .github/workflows/ 2>/dev/null | head -1)
if [ -z "$HAS_PROVENANCE" ]; then
  add_finding "low" "Sem SLSA provenance — atestado de build ausente" ".github/workflows/" ""
fi

# 6. Cosign signing
HAS_COSIGN=$(grep -lrE "(cosign|sigstore/cosign)" .github/workflows/ 2>/dev/null | head -1)
if [ -z "$HAS_COSIGN" ]; then
  add_finding "low" "Sem Cosign signing — artefatos não assinados" ".github/workflows/" ""
fi

# 7. Build com Date.now() / Math.random() (não-reprodutível)
log_info "Verificando reproducibilidade do build..."
NON_REPRO=$(rg -lE "(Date\.now\(\)|Math\.random\(\))" --type ts scripts/build* 2>/dev/null | head -1)
if [ -n "$NON_REPRO" ]; then
  add_finding "low" "Build script usa Date.now/Math.random — não-reprodutível" "$NON_REPRO" ""
fi

if [ "$FAIL" -eq 1 ]; then
  emit_result "$BLINDAR_AGENT" "failed" 1
  exit 1
fi

emit_result "$BLINDAR_AGENT" "passed" 0
exit 0
