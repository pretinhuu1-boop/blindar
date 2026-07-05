#!/usr/bin/env bash
# Materializa agente: i18n-tz
# TIMESTAMPTZ no schema, currency em BigInt cents, locales sync

BLINDAR_AGENT="check-i18n-tz"
source "$(dirname "$0")/_lib.sh"

log_section "Check: i18n-tz (TIMESTAMPTZ, BigInt cents, locales sync, IANA tz)"

IGNORE=(-g '!node_modules' -g '!dist' -g '!build' -g '!**/*.test.*')
load_intelligence_globs "$BLINDAR_AGENT"
FAIL=0

# 1. Prisma com DateTime sem timezone awareness
if is_prisma; then
  log_info "Verificando timezones no Prisma..."
  if grep -E "DateTime\s+@db\.Time\b" prisma/schema.prisma 2>/dev/null | grep -q .; then
    add_finding "high" "@db.Time detectado (sem timezone) — usar @db.Timestamptz" "prisma/schema.prisma" ""
    log_warn "@db.Time sem timezone"
  fi
fi

# 2. Currency em Float/Number
if has_file "prisma/schema.prisma"; then
  log_info "Verificando currency em BigInt cents..."
  MONEY_FLOAT=$(grep -cE "(price|amount|salary|cost|fee|total|value)\s+(Float|Decimal)" prisma/schema.prisma 2>/dev/null)
  if [ "$MONEY_FLOAT" -gt 0 ]; then
    add_finding "high" "$MONEY_FLOAT campo(s) de dinheiro em Float/Decimal — usar BigInt cents" "prisma/schema.prisma" ""
    log_fail "$MONEY_FLOAT campos de money em Float/Decimal"
    FAIL=1
  fi
fi

# 3. Lib i18n moderna (next-intl, @formatjs, vue-i18n) em projeto com UI
if has_file "package.json"; then
  log_info "Verificando lib i18n..."
  if grep -lE "(react|vue|svelte|next)" package.json 2>/dev/null | head -1 | grep -q .; then
    HAS_I18N=$(grep -cE "\"(next-intl|@formatjs|vue-i18n|i18next|svelte-i18n)\":" package.json 2>/dev/null)
    if [ "$HAS_I18N" -eq 0 ]; then
      add_finding "med" "Projeto com UI mas sem lib i18n — limita expansão internacional" "package.json" ""
    fi
  fi
fi

# 4. Telefone sem libphonenumber (E.164)
log_info "Buscando telefone sem normalização..."
TMP=$(mktemp)
rg -n "phone\s*:\s*String|telefone\s*:\s*String" --type ts --type prisma "${IGNORE[@]}" "${INTEL_GLOBS[@]}" > "$TMP" 2>/dev/null || true
PHONES=$(wc -l < "$TMP" || echo 0)
if [ "$PHONES" -gt 0 ]; then
  if ! grep -qE "libphonenumber" package.json 2>/dev/null; then
    add_finding "med" "$PHONES campo telefone sem libphonenumber-js — formatos inconsistentes" "" ""
  fi
fi
rm -f "$TMP"

# 5. Locales sync (chaves entre idiomas)
log_info "Verificando sync de locales..."
LOCALE_DIRS=$(find . -type d -name "locales" -not -path "./node_modules/*" 2>/dev/null | head -3)
if [ -n "$LOCALE_DIRS" ]; then
  for dir in $LOCALE_DIRS; do
    LANGS=$(ls "$dir" 2>/dev/null | head -10)
    LANG_COUNT=$(echo "$LANGS" | wc -l || echo 0)
    if [ "$LANG_COUNT" -gt 1 ]; then
      # Compara chaves entre primeiro e segundo idioma
      FIRST=$(echo "$LANGS" | head -1)
      SECOND=$(echo "$LANGS" | sed -n '2p')
      if [ -n "$FIRST" ] && [ -n "$SECOND" ]; then
        FIRST_KEYS=$(find "$dir/$FIRST" -name "*.json" -exec jq -r 'keys[]' {} \; 2>/dev/null | sort -u | wc -l || echo 0)
        SECOND_KEYS=$(find "$dir/$SECOND" -name "*.json" -exec jq -r 'keys[]' {} \; 2>/dev/null | sort -u | wc -l || echo 0)
        DIFF=$((FIRST_KEYS - SECOND_KEYS))
        if [ "${DIFF#-}" -gt 5 ]; then
          add_finding "med" "Locales desincronizados: $FIRST tem $FIRST_KEYS chaves, $SECOND tem $SECOND_KEYS" "$dir" ""
          log_warn "$dir desincronizado"
        fi
      fi
    fi
  done
fi

# 6. Date.now() sem timezone awareness em código
log_info "Buscando new Date() problemas..."
TMP=$(mktemp)
rg -n "new Date\(['\"]?20[0-9]{2}-" --type ts --type js "${IGNORE[@]}" "${INTEL_GLOBS[@]}" > "$TMP" 2>/dev/null || true
HARDCODED_DATES=$(wc -l < "$TMP" || echo 0)
if [ "$HARDCODED_DATES" -gt 3 ]; then
  add_finding "low" "$HARDCODED_DATES new Date('YYYY-MM-DD') hardcoded — pode dar drift entre fusos" "" ""
fi
rm -f "$TMP"

if [ "$FAIL" -eq 1 ]; then
  emit_result "$BLINDAR_AGENT" "failed" 1
  exit 1
fi

emit_result "$BLINDAR_AGENT" "passed" 0
exit 0
