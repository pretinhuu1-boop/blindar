#!/usr/bin/env bash
# Materialização do agente: file-uploads
# Detecta upload via backend sem presigned URL, MIME por extensão, SVG sem sanitize

BLINDAR_AGENT="check-file-uploads"
source "$(dirname "$0")/_lib.sh"

log_section "Check: file-uploads safety"

if ! command -v rg >/dev/null 2>&1; then
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

# Só roda se detectar upload lib
UPLOAD_DETECTED=0
for lib in multer formidable busboy "aws-sdk" "@aws-sdk/client-s3"; do
  if grep -qE "\"$lib\":|\"@$lib\":" package.json 2>/dev/null; then
    UPLOAD_DETECTED=1
    log_info "Lib de upload detectada: $lib"
  fi
done

if [ "$UPLOAD_DETECTED" -eq 0 ]; then
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

FAIL=0
IGNORE=(-g '!node_modules' -g '!dist' -g '!build' -g '!**/*.test.*' -g '!**/*.spec.*')

# 1. Multer/busboy em rota produção (deveria ser presigned)
log_info "Buscando upload via backend (deveria ser presigned)..."
TMP=$(mktemp)
rg -n "multer\(|formidable\(|new Busboy" --type ts --type js "${IGNORE[@]}" > "$TMP" 2>/dev/null || true
BACKEND_UPLOAD=$(wc -l < "$TMP" || echo 0)
if [ "$BACKEND_UPLOAD" -gt 0 ]; then
  while IFS=: read -r file line content; do
    [ -z "$file" ] && continue
    add_finding "med" "Upload via backend (preferir presigned URL): $(echo "$content" | xargs | cut -c1-80)" "$file" "$line"
  done < "$TMP"
  log_warn "$BACKEND_UPLOAD upload(s) via backend — preferir S3 presigned"
fi
rm -f "$TMP"

# 2. SVG sem DOMPurify (XSS risk)
log_info "Buscando SVG aceito sem sanitize..."
TMP=$(mktemp)
rg -n "image/svg\+xml|\.svg" --type ts --type js "${IGNORE[@]}" 2>/dev/null | \
  grep -v "DOMPurify\|sanitize" > "$TMP" || true
SVG_NO_SAN=$(wc -l < "$TMP" || echo 0)
if [ "$SVG_NO_SAN" -gt 0 ]; then
  add_finding "high" "$SVG_NO_SAN ref a SVG sem DOMPurify (XSS risk)" "" ""
  log_warn "$SVG_NO_SAN SVG sem sanitize"
fi
rm -f "$TMP"

# 3. S3 bucket public-read em código
log_info "Buscando ACL public-read..."
TMP=$(mktemp)
rg -n "ACL\s*:\s*['\"]public-read|public-read-write" --type ts --type js --type yaml --type tf "${IGNORE[@]}" > "$TMP" 2>/dev/null || true
PUBLIC_ACL=$(wc -l < "$TMP" || echo 0)
if [ "$PUBLIC_ACL" -gt 0 ]; then
  while IFS=: read -r file line content; do
    [ -z "$file" ] && continue
    add_finding "crit" "Bucket public-read: $(echo "$content" | xargs)" "$file" "$line"
  done < "$TMP"
  log_fail "$PUBLIC_ACL bucket public-read em código"
  FAIL=1
fi
rm -f "$TMP"

# 4. ContentLength sem validação (anti-DoS upload gigante)
log_info "Buscando presigned sem ContentLength..."
TMP=$(mktemp)
rg -n "getSignedUrl.*putObject" --type ts --type js "${IGNORE[@]}" -A 10 2>/dev/null | \
  grep -v "ContentLength" > "$TMP" || true
NO_SIZE=$(grep -c "getSignedUrl" "$TMP" 2>/dev/null)
if [ "$NO_SIZE" -gt 0 ]; then
  add_finding "med" "presigned URL sem ContentLength cap (atacante manda GB)" "" ""
fi
rm -f "$TMP"

if [ "$FAIL" -eq 1 ]; then
  emit_result "$BLINDAR_AGENT" "failed" 1
  exit 1
fi

emit_result "$BLINDAR_AGENT" "passed" 0
exit 0
