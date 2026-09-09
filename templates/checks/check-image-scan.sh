#!/usr/bin/env bash
# Materializa: image-scan — CVE da IMAGEM, não das dependências.
#
# `npm audit` e `check-deps-audit` olham o que você declarou no package.json.
# Nada ali enxerga o que veio junto na imagem base: openssl, glibc, zlib, curl,
# o runtime da própria linguagem. Um `node:20-slim` de seis meses atrás carrega
# dezenas de CVEs de sistema que nenhum lockfile menciona.
#
# Duas camadas, e as duas reportam:
#   ESTÁTICA  — a base está fixada por digest, ou é uma tag móvel? Roda sempre.
#   DINÂMICA  — trivy/grype na imagem de fato. Roda quando a imagem existe
#               localmente e o scanner responde. Quando não roda, o resultado é
#               `skipped` com missing_tool preenchido — nunca `passed` mudo.
BLINDAR_AGENT="check-image-scan"
source "$(dirname "$0")/_lib.sh"
log_section "Check: CVE da imagem de container (base + camadas de sistema)"

DF=""
for f in Dockerfile Dockerfile.prod Dockerfile.production docker/Dockerfile build/Dockerfile; do
  [ -f "$f" ] && { DF="$f"; break; }
done

IMAGEM="${BLINDAR_IMAGE:-}"
[ -z "$IMAGEM" ] && [ -f ".blindar/image.ref" ] && IMAGEM=$(tr -d '[:space:]' < .blindar/image.ref)

if [ -z "$DF" ] && [ -z "$IMAGEM" ]; then
  log_info "projeto não constrói imagem de container — não se aplica"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

# ─── Camada estática: a base é reprodutível? ───
# Tag móvel não é só falta de reprodutibilidade: é impossibilidade de auditar.
# "Foi escaneado" perde o sentido quando `node:20` de hoje não é o de ontem.
if [ -n "$DF" ]; then
  while IFS=: read -r ln txt; do
    [ -z "${ln:-}" ] && continue
    BASE=$(printf '%s' "$txt" | sed -E 's/^[[:space:]]*[Ff][Rr][Oo][Mm][[:space:]]+//; s/[[:space:]]+[Aa][Ss][[:space:]]+.*$//' | tr -d '\r')
    case "$BASE" in
      *@sha256:*)  log_pass "base fixada por digest: $BASE" ;;
      *:latest|*:latest@*)
        add_finding "high" "Imagem base '$BASE' usa tag :latest — o build de amanhã traz um sistema diferente do que foi auditado hoje, e nenhum scan tem validade" "$DF" "$ln" ;;
      *:*)
        add_finding "med" "Imagem base '$BASE' fixada só por tag, sem digest (@sha256:...) — a tag é móvel; o mantenedor republica e o conteúdo escaneado deixa de ser o conteúdo entregue" "$DF" "$ln" ;;
      scratch|\$*) : ;;
      *)
        add_finding "high" "Imagem base '$BASE' sem tag nenhuma (equivale a :latest) — conteúdo imprevisível a cada build" "$DF" "$ln" ;;
    esac
    [ -z "$IMAGEM" ] && IMAGEM="$BASE"
  done <<EOT
$(grep -nE '^[[:space:]]*[Ff][Rr][Oo][Mm][[:space:]]+' "$DF" 2>/dev/null | head -6)
EOT
fi

# ─── Camada dinâmica: escanear a imagem de verdade ───
SCANNER=""
command -v trivy >/dev/null 2>&1 && SCANNER="trivy"
[ -z "$SCANNER" ] && command -v grype >/dev/null 2>&1 && SCANNER="grype"

RODOU=0
if [ -z "$SCANNER" ]; then
  log_warn "nem trivy nem grype instalados — a camada de CVE da imagem NÃO foi medida"
  log_warn "instale: winget install AquaSecurity.Trivy | brew install trivy | apt install trivy"
  BLINDAR_MISSING_TOOL="trivy|grype"
elif [ -z "$IMAGEM" ] || [ "${IMAGEM#\$}" != "$IMAGEM" ]; then
  log_warn "não consegui resolver a referência da imagem — informe com BLINDAR_IMAGE=<ref> ou .blindar/image.ref"
  BLINDAR_MISSING_TOOL="imagem-nao-resolvida"
elif ! command -v docker >/dev/null 2>&1 || ! docker image inspect "$IMAGEM" >/dev/null 2>&1; then
  # De propósito NÃO puxa a imagem por conta própria: um check não deve baixar
  # gigabytes nem depender de rede para dar veredito. Quem quiser o scan
  # completo constrói/puxa antes, ou liga BLINDAR_IMAGE_PULL=1.
  if [ "${BLINDAR_IMAGE_PULL:-0}" = "1" ] && command -v docker >/dev/null 2>&1; then
    log_info "BLINDAR_IMAGE_PULL=1 — puxando $IMAGEM"
    docker pull "$IMAGEM" >/dev/null 2>&1 || true
  fi
  if command -v docker >/dev/null 2>&1 && docker image inspect "$IMAGEM" >/dev/null 2>&1; then
    RODOU=1
  else
    log_warn "imagem '$IMAGEM' não está disponível localmente — a camada de CVE NÃO foi medida"
    log_warn "construa (docker build -t <ref> .) ou rode com BLINDAR_IMAGE_PULL=1"
    BLINDAR_MISSING_TOOL="imagem-indisponivel:$IMAGEM"
  fi
else
  RODOU=1
fi

if [ "$RODOU" -eq 1 ]; then
  log_info "escaneando imagem $IMAGEM com $SCANNER ..."
  SAIDA=""
  if [ "$SCANNER" = "trivy" ]; then
    if command -v timeout >/dev/null 2>&1; then
      SAIDA=$(timeout 300 trivy image --quiet --scanners vuln --severity CRITICAL,HIGH \
        --format json "$IMAGEM" 2>/dev/null)
    else
      SAIDA=$(trivy image --quiet --scanners vuln --severity CRITICAL,HIGH --format json "$IMAGEM" 2>/dev/null)
    fi
  else
    SAIDA=$(grype "$IMAGEM" -o json --quiet 2>/dev/null)
  fi

  # Binário que responde --version e falha no scan real é pior que ausente:
  # some da lista de pendências e o verde vira mentira.
  if [ -z "$SAIDA" ]; then
    log_warn "$SCANNER está instalado mas não produziu saída para '$IMAGEM' — NÃO leia como imagem limpa"
    BLINDAR_MISSING_TOOL="$SCANNER:sem-saida"
  elif command -v node >/dev/null 2>&1; then
    export IMG_SCAN_RAW="$SAIDA" IMG_SCAN_TOOL="$SCANNER"
    while IFS='|' read -r sev id pkg titulo; do
      [ -z "${sev:-}" ] && continue
      add_finding "$sev" "CVE na imagem: $id em $pkg — $titulo" "${DF:-$IMAGEM}" ""
    done <<EOT
$(node -e '
const raw = process.env.IMG_SCAN_RAW || "";
const tool = process.env.IMG_SCAN_TOOL;
const lim = (s) => String(s || "").replace(/[\r\n\t|]+/g, " ").slice(0, 160);
let out = [];
try {
  const d = JSON.parse(raw);
  if (tool === "trivy") {
    for (const r of d.Results || [])
      for (const v of r.Vulnerabilities || [])
        out.push([v.Severity === "CRITICAL" ? "crit" : "high", v.VulnerabilityID,
                  (v.PkgName || "") + "@" + (v.InstalledVersion || ""), lim(v.Title || v.Description)]);
  } else {
    for (const m of d.matches || []) {
      const s = String(m.vulnerability?.severity || "").toUpperCase();
      if (s !== "CRITICAL" && s !== "HIGH") continue;
      out.push([s === "CRITICAL" ? "crit" : "high", m.vulnerability?.id,
                (m.artifact?.name || "") + "@" + (m.artifact?.version || ""), lim(m.vulnerability?.description)]);
    }
  }
} catch (e) { process.exit(0); }
for (const l of out.slice(0, 25)) console.log(l.join("|"));
' 2>/dev/null)
EOT
    BLINDAR_EVIDENCE_KIND="dynamic"
    mark_exercised
    log_info "scan de imagem concluído"
  else
    log_warn "node ausente — não consigo parsear a saída do $SCANNER"
    BLINDAR_MISSING_TOOL="node"
  fi
fi

if [ "${#FINDINGS[@]}" -gt 0 ]; then
  case "${FINDINGS[*]}" in
    *'"severity":"high"'*|*'"severity":"crit"'*) emit_result "$BLINDAR_AGENT" "failed" 1; exit 1 ;;
  esac
  emit_result "$BLINDAR_AGENT" "failed" 0
  exit 0
fi

# Sem achado estático E sem scan executado = ninguém mediu a imagem. Isso é
# ausência de sinal, e ausência de sinal nunca é aprovação.
if [ "$RODOU" -eq 0 ]; then
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

log_pass "imagem escaneada, sem CVE crítico/alto"
emit_result "$BLINDAR_AGENT" "passed" 0
exit 0
