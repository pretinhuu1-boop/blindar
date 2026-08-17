#!/usr/bin/env bash
# Materializa agente: horizontal-scale
# O que funciona com UMA réplica e quebra com DUAS.
#
# Este é o modo de falha mais caro de escalar: nada quebra em homologação, onde
# roda uma instância. Quebra em produção, quando alguém sobe a segunda — e
# quebra de forma intermitente, porque depende de qual réplica atendeu a
# requisição. O usuário desloga "às vezes". O rate limit segura "às vezes". A
# mensagem do chat chega "às vezes".
#
# Intermitente por roteamento é o pior tipo de bug para diagnosticar: não
# reproduz na sua máquina, não reproduz em staging, e o log de uma réplica só
# não conta a história.
#
# O que este check NÃO faz: julgar se você deveria escalar. Uma instância só é
# uma decisão legítima. O que ele diz é se o código SUPORTA a segunda — porque a
# hora de descobrir não é durante o incidente.
#
# O balanceador em si (nginx, traefik, ALB, health check do LB, terminação TLS)
# é máquina, não código: quem verifica é o `ancorar`.

BLINDAR_AGENT="check-horizontal-scale"
source "$(dirname "$0")/_lib.sh"

log_section "Check: horizontal-scale (o que quebra na segunda réplica)"

if ! command -v rg >/dev/null 2>&1; then
  BLINDAR_MISSING_TOOL="rg"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

# Só faz sentido em backend long-running: script e CLI não têm réplica.
BACKEND=0
for lib in "@nestjs/core" express fastify koa hapi "socket.io" fastapi django flask; do
  if grep -qE "\"$lib\"|$lib" package.json pyproject.toml requirements.txt 2>/dev/null; then
    BACKEND=1
  fi
done
if [ "$BACKEND" -eq 0 ]; then
  log_info "Não é backend long-running — não há segunda réplica para quebrar"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

IGNORE=(-g '!.next' -g '!.nuxt' -g '!out' -g '!.svelte-kit' -g '!node_modules' -g '!dist' -g '!build' -g '!**/*.test.*' -g '!**/*.spec.*')
load_intelligence_globs "$BLINDAR_AGENT"

# ─── 1. Sessão em memória ───
# O campeão. `express-session` sem `store` usa MemoryStore, que o próprio pacote
# avisa no console não servir para produção — e o aviso vira ruído que ninguém lê.
# Com duas réplicas o usuário desloga toda vez que o balanceador o manda para a
# outra, porque a sessão dele não existe lá.
SESSION_FILES=$(rg -l "express-session|MemoryStore|cookie-session" "${IGNORE[@]}" "${INTEL_GLOBS[@]}" 2>/dev/null || true)
if [ -n "$SESSION_FILES" ]; then
  # Store compartilhado: connect-redis, connect-mongo, connect-pg-simple etc.
  if ! rg -q "connect-redis|connect-mongo|connect-pg|RedisStore|MongoStore|session-file-store|store:" \
       "${IGNORE[@]}" "${INTEL_GLOBS[@]}" 2>/dev/null; then
    while IFS= read -r _f; do
      [ -z "$_f" ] && continue
      _l=$(rg -n "express-session|MemoryStore|cookie-session" "$_f" 2>/dev/null | head -1 | cut -d: -f1)
      add_finding "high" "Sessão em memória do processo (sem store compartilhado) — com 2+ réplicas o usuário desloga quando o balanceador o manda para a outra instância. Use connect-redis ou equivalente" "$_f" "${_l:-}"
      break
    done <<< "$SESSION_FILES"
  fi
fi

# ─── 2. Rate limit por instância ───
# Mais perigoso que não ter, porque parece ter. `express-rate-limit` sem `store`
# guarda a contagem na memória do processo: com N réplicas o atacante recebe N×
# o limite configurado, e o painel mostra o rate limit "ativo".
#
# O check-rate-limit verifica se EXISTE rate-limit. Este verifica se ele é
# COMPARTILHADO — e passar naquele sem passar neste é proteção de fachada.
if rg -q "express-rate-limit|rateLimit\(|@nestjs/throttler|slowDown" "${IGNORE[@]}" "${INTEL_GLOBS[@]}" 2>/dev/null; then
  if ! rg -qi "rate-limit-redis|RateLimitRedis|ThrottlerStorageRedis|rate-limit-flexible|store:\s*new" \
       "${IGNORE[@]}" "${INTEL_GLOBS[@]}" 2>/dev/null; then
    _f=$(rg -l "express-rate-limit|rateLimit\(|@nestjs/throttler" "${IGNORE[@]}" "${INTEL_GLOBS[@]}" 2>/dev/null | head -1)
    add_finding "high" "Rate limit sem store compartilhado — cada réplica conta sozinha, então o limite efetivo é N× o configurado. Passa no check-rate-limit e não protege" "${_f:-}" ""
  fi
fi

# ─── 3. WebSocket sem adapter ───
# `io.emit` num processo alcança só os sockets conectados NAQUELE processo. Com
# duas réplicas, metade da sala não recebe a mensagem — e o remetente vê a
# própria mensagem, então parece que funcionou.
if rg -q "socket\.io|new Server\(.*http|io\.emit|io\.to\(" "${IGNORE[@]}" "${INTEL_GLOBS[@]}" 2>/dev/null; then
  if ! rg -q "socket.io-redis|@socket.io/redis-adapter|createAdapter|socket.io-emitter|cluster-adapter" \
       "${IGNORE[@]}" "${INTEL_GLOBS[@]}" 2>/dev/null; then
    _f=$(rg -l "socket\.io|io\.emit" "${IGNORE[@]}" "${INTEL_GLOBS[@]}" 2>/dev/null | head -1)
    add_finding "high" "socket.io sem adapter Redis — broadcast só alcança quem está na mesma instância. Metade da sala não recebe, e o remetente vê a própria mensagem" "${_f:-}" ""
  fi
fi

# ─── 4. Upload em disco local ───
# Arquivo gravado em ./uploads existe numa réplica só. O GET seguinte cai na
# outra e devolve 404 — de forma intermitente, o que faz parecer bug de rede.
# Em container, some no primeiro deploy.
if rg -q "multer\(\{[^}]*dest|diskStorage|writeFileSync\(.*uploads|createWriteStream\(.*uploads" \
     "${IGNORE[@]}" "${INTEL_GLOBS[@]}" 2>/dev/null; then
  if ! rg -qi "@aws-sdk/client-s3|aws-sdk.*S3|@google-cloud/storage|minio|cloudinary|BlobServiceClient|presigned" \
       "${IGNORE[@]}" "${INTEL_GLOBS[@]}" 2>/dev/null; then
    _f=$(rg -l "multer\(\{[^}]*dest|diskStorage" "${IGNORE[@]}" "${INTEL_GLOBS[@]}" 2>/dev/null | head -1)
    add_finding "high" "Upload gravado em disco local — o arquivo existe numa réplica só, e o GET seguinte cai na outra e dá 404 de forma intermitente. Em container, some no deploy" "${_f:-}" ""
  fi
fi

# ─── 5. Cache local usado como fonte da verdade ───
# `new Map()` como cache é legítimo. Vira problema quando é a única cópia de algo
# que precisa ser consistente entre réplicas — token revogado, feature flag,
# contador de tentativa. Aqui só dá para levantar suspeita, então é `med` e o
# texto pede verificação em vez de afirmar.
MAPCACHE=$(rg -c "new Map\(\)|new Set\(\)" "${IGNORE[@]}" "${INTEL_GLOBS[@]}" 2>/dev/null | awk -F: '{s+=$NF} END{print s+0}')
if [ "${MAPCACHE:-0}" -gt 0 ]; then
  if rg -q "revok|blacklist|denylist|featureFlag|feature_flag|attempts|tentativa|idempot" \
       "${IGNORE[@]}" "${INTEL_GLOBS[@]}" 2>/dev/null; then
    if ! rg -qi "redis|memcached|dynamodb|etcd|consul" "${IGNORE[@]}" "${INTEL_GLOBS[@]}" 2>/dev/null; then
      add_finding "med" "Estado que precisa ser consistente entre réplicas (revogação/flag/tentativa) parece viver em Map/Set do processo — confirme se há armazenamento compartilhado" "" ""
    fi
  fi
fi

# ─── 6. Webhook sem idempotência ───
# Todo provedor sério reenvia webhook: Stripe, Mercado Pago, GitHub. Sem chave de
# idempotência, o reenvio credita duas vezes. Com N réplicas isso piora, porque
# duas entregas simultâneas caem em processos diferentes e nem um lock local
# salva.
if rg -q "webhook|/hooks/|stripe.*constructEvent|mercadopago" "${IGNORE[@]}" "${INTEL_GLOBS[@]}" 2>/dev/null; then
  # O padrão precisa casar CÓDIGO, não a palavra solta: um comentário dizendo
  # "webhook sem idempotência" satisfazia o guard e calava o check. Mencionar o
  # problema não é resolvê-lo — e o fixture vulnerável provou isso na prática.
  if ! rg -qi "idempotency[_-]?key|already_processed|processed_events|event_id.*unique|unique.*event_id|SETNX.*event|NX:\s*true" \
       "${IGNORE[@]}" "${INTEL_GLOBS[@]}" 2>/dev/null; then
    _f=$(rg -l "webhook|stripe.*constructEvent" "${IGNORE[@]}" "${INTEL_GLOBS[@]}" 2>/dev/null | head -1)
    add_finding "high" "Webhook sem controle de idempotência — todo provedor reenvia, e reenvio sem deduplicação credita duas vezes. Com várias réplicas, duas entregas simultâneas caem em processos diferentes e lock local não segura" "${_f:-}" ""
  fi
fi

# ─── 7. Sticky session declarada na infra ───
# `sessionAffinity: ClientIP` e `ip_hash` funcionam, e escondem o problema 1: o
# app continua sem estado compartilhado, só que agora depende do balanceador
# nunca remanejar ninguém. No primeiro redeploy, ou quando uma réplica cai, a
# sessão se perde do mesmo jeito.
if rg -q "sessionAffinity|ip_hash|sticky|affinity: ClientIP" -g '*.yml' -g '*.yaml' -g '*.conf' \
     -g 'nginx*' "${IGNORE[@]}" 2>/dev/null; then
  add_finding "med" "Sticky session configurada na infra — funciona, mas mascara ausência de estado compartilhado: quando uma réplica cai ou há redeploy, a sessão se perde igual" "" ""
fi

if [ "${#FINDINGS[@]}" -gt 0 ]; then
  emit_result "$BLINDAR_AGENT" "failed" 1
  exit 1
fi

log_pass "nada que quebre ao subir a segunda réplica"
emit_result "$BLINDAR_AGENT" "passed" 0
exit 0
