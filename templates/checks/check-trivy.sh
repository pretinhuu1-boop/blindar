#!/usr/bin/env bash
# Materializa: trivy (Aqua — vuln + secret + misconfig scanner)
BLINDAR_AGENT="check-trivy"
source "$(dirname "$0")/_lib.sh"
log_section "Check: trivy (vuln + secret + misconfig)"

# 1. Detecta binário
if ! command -v trivy >/dev/null 2>&1; then
  log_warn "trivy não encontrado — pulando"
  log_info "Instale: brew install trivy (ou veja https://aquasecurity.github.io/trivy)"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

if ! command -v node >/dev/null 2>&1; then
  add_finding "med" "node ausente — não consigo parsear output do trivy" "" ""
  emit_result "$BLINDAR_AGENT" "failed" 1
  exit 1
fi

# 2. Roda fs scan (sempre) + config scan (se houver Dockerfile)
HAS_DOCKERFILE=0
[ -f "Dockerfile" ] && HAS_DOCKERFILE=1

run_trivy() {
  local subcmd="$1"; shift
  if command -v timeout >/dev/null 2>&1; then
    timeout 180 trivy "$subcmd" "$@" 2>/dev/null
  else
    trivy "$subcmd" "$@" 2>/dev/null
  fi
}

log_info "Rodando trivy fs (vuln + secret + misconfig) ..."
FS_JSON=$(run_trivy fs --format=json --scanners vuln,secret,misconfig . )
FS_RC=$?

CONFIG_JSON=""
if [ "$HAS_DOCKERFILE" -eq 1 ]; then
  log_info "Dockerfile detectado — rodando trivy config ..."
  CONFIG_JSON=$(run_trivy config --format=json . )
fi

if [ "$FS_RC" -eq 124 ]; then
  add_finding "med" "trivy fs timeout após 180s" "" ""
fi

# 3. Parse via Node
parse_trivy() {
  local raw="$1"
  local source_tag="$2"
  [ -z "$raw" ] && return 0
  export TRIVY_JSON_RAW="$raw"
  export TRIVY_SOURCE_TAG="$source_tag"
  node -e '
try {
  const raw = process.env.TRIVY_JSON_RAW || "";
  const source = process.env.TRIVY_SOURCE_TAG || "trivy";
  if (!raw.trim()) process.exit(0);
  const data = JSON.parse(raw);
  const results = data.Results || [];
  const out = [];
  const mapSev = (s) => {
    s = String(s || "").toUpperCase();
    if (s === "CRITICAL") return "crit";
    if (s === "HIGH") return "high";
    if (s === "MEDIUM") return "med";
    if (s === "LOW") return "low";
    return "low";
  };
  const clean = (s) => String(s || "").replace(/[\r\n\t]+/g, " ").slice(0, 200);
  for (const r of results) {
    const target = r.Target || "";
    const vulns = r.Vulnerabilities || [];
    for (const v of vulns) {
      const id = v.VulnerabilityID || "UNKNOWN";
      const sev = mapSev(v.Severity);
      const title = clean(v.Title || v.Description || "");
      const pkg = (v.PkgName || "") + (v.InstalledVersion ? "@" + v.InstalledVersion : "");
      out.push([sev, "vuln", id, title, pkg || target].join("\t"));
    }
    const miscs = r.Misconfigurations || [];
    for (const m of miscs) {
      const id = m.ID || "UNKNOWN";
      const sev = mapSev(m.Severity);
      const title = clean(m.Title || m.Description || "");
      out.push([sev, "misconfig", id, title, target].join("\t"));
    }
    const secrets = r.Secrets || [];
    for (const s of secrets) {
      const id = s.RuleID || "UNKNOWN";
      const sev = mapSev(s.Severity);
      const title = clean(s.Title || s.Match || "");
      out.push([sev, "secret", id, title, target].join("\t"));
    }
  }
  console.log(out.join("\n"));
} catch (e) {
  process.stderr.write("parse-error: " + e.message);
  process.exit(2);
}
' 2>/dev/null
  unset TRIVY_JSON_RAW TRIVY_SOURCE_TAG
}

FS_PARSED=$(parse_trivy "$FS_JSON" "fs")
CONFIG_PARSED=""
if [ -n "$CONFIG_JSON" ]; then
  CONFIG_PARSED=$(parse_trivy "$CONFIG_JSON" "config")
fi

# 4. Materializa findings — formato: sev\tkind\tid\ttitle\tfile
process_parsed() {
  local parsed="$1"
  local src="$2"
  [ -z "$parsed" ] && return 0
  while IFS=$'\t' read -r sev kind id title file; do
    [ -z "$sev" ] && continue
    add_finding "$sev" "[trivy:$src:$kind:$id] $title" "$file" ""
  done <<< "$parsed"
}

process_parsed "$FS_PARSED" "fs"
process_parsed "$CONFIG_PARSED" "config"

# 5. Gate: SÓ crit bloqueia (high de Trivy costuma ter ruído de scan profundo)
CRITS=$(printf '%s\n' "${FINDINGS[@]:-}" | grep -c '"severity":"crit"' 2>/dev/null || echo 0)
if [ "${CRITS:-0}" -gt 0 ]; then
  emit_result "$BLINDAR_AGENT" "failed" 1
  exit 1
fi
emit_result "$BLINDAR_AGENT" "passed" 0
