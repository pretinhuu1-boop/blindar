#!/usr/bin/env bash
# Materializa: osv-scanner (Google OSV.dev vuln scanner em lockfiles)
BLINDAR_AGENT="check-osv-scanner"
source "$(dirname "$0")/_lib.sh"
log_section "Check: osv-scanner (vulns em lockfiles via OSV.dev)"

# 1. Detecta binário
if ! command -v osv-scanner >/dev/null 2>&1; then
  log_warn "osv-scanner não encontrado — pulando"
  log_info "Instale: brew install osv-scanner OU go install github.com/google/osv-scanner/cmd/osv-scanner@latest"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

# 2. Roda scan (timeout 120s; --recursive cobre lockfiles aninhados)
log_info "Rodando osv-scanner --recursive ..."
OSV_JSON=""
if command -v timeout >/dev/null 2>&1; then
  OSV_JSON=$(timeout 120 osv-scanner --format=json --recursive . 2>/dev/null)
else
  OSV_JSON=$(osv-scanner --format=json --recursive . 2>/dev/null)
fi
OSV_RC=$?

# osv-scanner retorna exit 1 quando acha vulns (normal); 127/124 = erro real.
if [ "$OSV_RC" -eq 124 ]; then
  add_finding "med" "osv-scanner timeout após 120s — projeto muito grande?" "" ""
  emit_result "$BLINDAR_AGENT" "failed" 1
  exit 1
fi

if [ -z "$OSV_JSON" ]; then
  log_info "Nenhum output do osv-scanner (sem lockfiles ou sem vulns)"
  emit_result "$BLINDAR_AGENT" "passed" 0
  exit 0
fi

# 3. Parse via Node (sem dependência de jq)
if ! command -v node >/dev/null 2>&1; then
  add_finding "med" "node ausente — não consigo parsear output do osv-scanner" "" ""
  emit_result "$BLINDAR_AGENT" "failed" 1
  exit 1
fi

# Exporta JSON em env pra evitar problema de quoting
export OSV_JSON_RAW="$OSV_JSON"

PARSED=$(node -e '
try {
  const raw = process.env.OSV_JSON_RAW || "";
  if (!raw.trim()) { process.exit(0); }
  const data = JSON.parse(raw);
  const results = data.results || [];
  const out = [];
  for (const r of results) {
    const packages = r.packages || [];
    for (const p of packages) {
      const pkgName = (p.package && p.package.name) || "";
      const vulns = p.vulnerabilities || [];
      for (const v of vulns) {
        const id = v.id || "UNKNOWN";
        const summary = (v.summary || v.details || "").replace(/[\r\n]+/g, " ").slice(0, 200);
        // Pega maior CVSS score disponível
        let score = null;
        const sevArr = v.severity || [];
        for (const s of sevArr) {
          if (s.score) {
            // CVSS vector ou número
            const m = String(s.score).match(/[\d.]+$/);
            if (m) {
              const n = parseFloat(m[0]);
              if (!isNaN(n) && (score === null || n > score)) score = n;
            }
          }
        }
        let sev;
        if (score === null) sev = "high";
        else if (score >= 9.0) sev = "crit";
        else if (score >= 7.0) sev = "high";
        else if (score >= 4.0) sev = "med";
        else sev = "low";
        out.push([sev, id, summary, pkgName].join("\t"));
      }
    }
  }
  console.log(out.join("\n"));
} catch (e) {
  process.stderr.write("parse-error: " + e.message);
  process.exit(2);
}
' 2>/dev/null)

unset OSV_JSON_RAW

# 4. Materializa findings
if [ -n "$PARSED" ]; then
  while IFS=$'\t' read -r sev id summary pkg; do
    [ -z "$sev" ] && continue
    add_finding "$sev" "[OSV:$id] $summary" "$pkg" ""
  done <<< "$PARSED"
fi

# 5. Gate: crit + high bloqueiam
CRITS=$(printf '%s\n' "${FINDINGS[@]:-}" | grep -c '"severity":"crit"' 2>/dev/null)
HIGHS=$(printf '%s\n' "${FINDINGS[@]:-}" | grep -c '"severity":"high"' 2>/dev/null)
if [ "${CRITS:-0}" -gt 0 ] || [ "${HIGHS:-0}" -gt 0 ]; then
  emit_result "$BLINDAR_AGENT" "failed" 1
  exit 1
fi
emit_result "$BLINDAR_AGENT" "passed" 0
