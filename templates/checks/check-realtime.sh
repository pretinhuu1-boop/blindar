#!/usr/bin/env bash
# Materializa: realtime — WS auth handshake, rooms multi-tenant, heartbeat
BLINDAR_AGENT="check-realtime"
source "$(dirname "$0")/_lib.sh"
log_section "Check: realtime (WS/SSE auth + rooms multi-tenant)"

if ! command -v rg >/dev/null 2>&1; then emit_result "$BLINDAR_AGENT" "skipped" 0; exit 0; fi

HAS_WS=0
for lib in "socket.io" ws "@nestjs/websockets" "graphql-ws" yjs liveblocks; do
  grep -qE "\"$lib\":" package.json 2>/dev/null && HAS_WS=1
done
if [ "$HAS_WS" -eq 0 ]; then emit_result "$BLINDAR_AGENT" "skipped" 0; exit 0; fi

IGNORE=('!node_modules' '!dist' '!**/*.test.*')

# 1. io.on connection sem auth
TMP=$(mktemp)
rg -nE "io\.on\(['\"]connection" --type ts "${IGNORE[@]}" -A 8 2>/dev/null | grep -v "auth\|verify\|jwt" > "$TMP" || true
NO_AUTH=$(grep -c "io.on" "$TMP" 2>/dev/null || echo 0)
[ "$NO_AUTH" -gt 0 ] && add_finding "crit" "$NO_AUTH socket.on('connection') sem auth — qualquer um conecta" "" ""
rm -f "$TMP"

# 2. Broadcast sem tenant namespace
TMP=$(mktemp)
rg -nE "io\.emit\(" --type ts "${IGNORE[@]}" 2>/dev/null | grep -v "tenant:\|user:\|room:" > "$TMP" || true
BROADCAST_LEAK=$(wc -l < "$TMP" || echo 0)
[ "$BROADCAST_LEAK" -gt 0 ] && add_finding "high" "$BROADCAST_LEAK io.emit sem namespace — vaza cross-tenant" "" ""
rm -f "$TMP"

# 3. Token em URL path (vaza em logs)
URL_TOKEN=$(rg -cE "io\(['\"]ws://.*token=" --type ts "${IGNORE[@]}" 2>/dev/null | wc -l || echo 0)
[ "$URL_TOKEN" -gt 0 ] && add_finding "high" "Token em URL WS (vaza em logs/proxies)" "" ""

# 4. Sem heartbeat config
HAS_HEARTBEAT=$(rg -lE "(pingInterval|pingTimeout|heartbeat)" --type ts "${IGNORE[@]}" 2>/dev/null | head -1)
[ -z "$HAS_HEARTBEAT" ] && add_finding "med" "Sem heartbeat configurado — conexões zumbi consomem RAM" "" ""

CRITS=$(printf '%s\n' "${FINDINGS[@]}" | grep -c '"severity":"crit"' || echo 0)
[ "$CRITS" -gt 0 ] && { emit_result "$BLINDAR_AGENT" "failed" 1; exit 1; }
emit_result "$BLINDAR_AGENT" "passed" 0
