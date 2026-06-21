#!/usr/bin/env bash
# Materialização do agente: patch-management + supply-chain
# Roda npm audit / pip-audit / go list -m / cargo audit conforme stack detectada
# Bloqueia em vulnerabilidades HIGH ou CRITICAL.

BLINDAR_AGENT="check-deps-audit"
source "$(dirname "$0")/_lib.sh"

log_section "Check: dependências vulneráveis"

FAIL=0

if is_nodejs; then
  log_info "Detectado Node.js — npm audit"
  TMP=$(mktemp)
  if npm audit --audit-level=high --json > "$TMP" 2>/dev/null; then
    log_pass "Zero vulns HIGH/CRITICAL"
  else
    HIGH=$(jq '.metadata.vulnerabilities.high // 0' "$TMP" 2>/dev/null || echo 0)
    CRIT=$(jq '.metadata.vulnerabilities.critical // 0' "$TMP" 2>/dev/null || echo 0)
    log_fail "Vulnerabilidades: $CRIT critical, $HIGH high"
    add_finding "crit" "$CRIT vulnerabilidade(s) critical em deps Node" "package.json" ""
    add_finding "high" "$HIGH vulnerabilidade(s) high em deps Node" "package.json" ""
    FAIL=1
  fi
  rm -f "$TMP"
fi

if is_python; then
  log_info "Detectado Python — pip-audit"
  if command -v pip-audit >/dev/null 2>&1; then
    if pip-audit --strict 2>&1; then
      log_pass "Zero vulns Python"
    else
      add_finding "high" "Vulnerabilidades em deps Python" "requirements.txt" ""
      FAIL=1
    fi
  else
    log_warn "pip-audit não instalado. Instale: pip install pip-audit"
  fi
fi

if is_go; then
  log_info "Detectado Go — govulncheck"
  if command -v govulncheck >/dev/null 2>&1; then
    if govulncheck ./...; then
      log_pass "Zero vulns Go"
    else
      add_finding "high" "Vulnerabilidades em deps Go" "go.mod" ""
      FAIL=1
    fi
  else
    log_warn "govulncheck não instalado. Instale: go install golang.org/x/vuln/cmd/govulncheck@latest"
  fi
fi

if is_rust; then
  log_info "Detectado Rust — cargo audit"
  if command -v cargo-audit >/dev/null 2>&1; then
    if cargo audit; then
      log_pass "Zero vulns Rust"
    else
      add_finding "high" "Vulnerabilidades em deps Rust" "Cargo.toml" ""
      FAIL=1
    fi
  else
    log_warn "cargo-audit não instalado. Instale: cargo install cargo-audit"
  fi
fi

# Trivy pra container (se Dockerfile presente)
if has_file "Dockerfile" && command -v trivy >/dev/null 2>&1; then
  log_info "Detectado Dockerfile — trivy fs"
  if trivy fs --severity HIGH,CRITICAL --exit-code 1 --format json --output /tmp/trivy.json . 2>/dev/null; then
    log_pass "Zero vulns no filesystem (trivy)"
  else
    COUNT=$(jq '[.Results[]?.Vulnerabilities[]?] | length' /tmp/trivy.json 2>/dev/null || echo 0)
    add_finding "high" "$COUNT vulnerabilidade(s) trivy (HIGH+CRIT)" "Dockerfile" ""
    FAIL=1
  fi
fi

if [ "$FAIL" -eq 1 ]; then
  emit_result "$BLINDAR_AGENT" "failed" 1
  exit 1
fi

emit_result "$BLINDAR_AGENT" "passed" 0
exit 0
