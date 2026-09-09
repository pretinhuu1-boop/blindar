#!/usr/bin/env bash
# Materializa: dsr-automation — o titular consegue exercer o direito dele?
#
# LGPD art. 18 e GDPR art. 15–17 dão ao titular direito de ACESSO (receber cópia
# do que você guarda) e de ELIMINAÇÃO. O prazo corre a partir do pedido, não a
# partir do dia em que alguém lembrar de escrever o script. Sem mecanismo, o
# primeiro pedido vira um SELECT manual feito às pressas por um dev com acesso
# ao banco de produção — que é exatamente o oposto do que a lei quer.
#
# Segunda armadilha: "eliminar" com soft delete. `deleted_at = now()` esconde da
# UI e mantém o dado. Para o regulador o dado continua sendo tratado.
BLINDAR_AGENT="check-dsr-automation"
source "$(dirname "$0")/_lib.sh"
log_section "Check: pedido do titular — exportar e eliminar (LGPD art. 18 / GDPR art. 15-17)"

if ! has_personal_data; then
  log_info "sem sinal de titular de dado — não se aplica"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

EXPORTA=$(scan_src '(export(User|Personal|Subject)Data|data[_-]?export|exportar[_-]?dados|/privacy/export|/lgpd/(export|dados)|/gdpr/(export|access)|subject[_-]?access[_-]?request|portabilidade)' | head -3)
APAGA=$(scan_src '(delete(User|Account|Personal)|erase(User|Personal)|anonymiz|anonimiz|right[_-]?to[_-]?(be[_-]?forgotten|erasure)|/privacy/delete|/lgpd/(eliminar|excluir)|elimina(r|cao|ção)[_-]?(dados|conta))' | head -3)

if [ -z "$EXPORTA" ]; then
  add_finding "med" \
    "Sem mecanismo de EXPORTAÇÃO de dados do titular (LGPD art. 18, II e V / GDPR art. 15). O prazo legal corre do pedido; sem rotina, o primeiro pedido vira consulta manual em produção." "" ""
else
  log_pass "exportação de dados do titular encontrada"
fi

if [ -z "$APAGA" ]; then
  add_finding "med" \
    "Sem mecanismo de ELIMINAÇÃO de dados do titular (LGPD art. 18, VI / GDPR art. 17)." "" ""
else
  log_pass "eliminação de dados do titular encontrada"
  # Existe rota de eliminação, mas o que ela faz é soft delete e nada mais?
  TEM_SOFT=$(scan_src '(deleted_?[Aa]t|deletedAt|is_?deleted)' | head -1)
  TEM_REAL=$(scan_src '(anonymiz|anonimiz|\.delete\(|DELETE FROM|hard[_-]?delete|purge|destroy\(|deleteMany\()' | head -1)
  if [ -n "$TEM_SOFT" ] && [ -z "$TEM_REAL" ]; then
    ARQ=$(printf '%s' "$TEM_SOFT" | cut -d: -f1)
    LN=$(printf '%s' "$TEM_SOFT" | cut -d: -f2)
    add_finding "med" \
      "Eliminação implementada só como soft delete (deleted_at) — o dado continua no banco e continua sendo tratado. Para o regulador isso não é eliminação: é ocultação. Exija remoção física ou anonimização irreversível na rotina do titular." "$ARQ" "$LN"
  fi
fi

if [ "${#FINDINGS[@]}" -gt 0 ]; then
  emit_result "$BLINDAR_AGENT" "failed" 0
  exit 0
fi
log_pass "titular consegue exportar e eliminar"
emit_result "$BLINDAR_AGENT" "passed" 0
exit 0
