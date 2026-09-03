#!/usr/bin/env bash
# Materializa: container-hardening — o container roda como root e sem teto.
#
# Dois problemas distintos, os dois invisíveis enquanto tudo vai bem:
#
# 1. ROOT. `USER` ausente no Dockerfile significa uid 0 dentro do container. Uma
#    RCE que seria "escrever num diretório do app" vira "escrever em qualquer
#    lugar do rootfs", e o caminho até o host fica curto demais.
# 2. SEM LIMITE. Container sem `mem_limit`/`cpus` come toda a máquina. Numa VPS
#    com vizinhos — o caso normal — um vazamento de memória no seu serviço
#    derruba o banco de outro projeto. O sintoma aparece no vizinho.
#
# Isto é leitura de arquivo: Dockerfile e compose. Nada aqui exige o host no ar.
BLINDAR_AGENT="check-container-hardening"
source "$(dirname "$0")/_lib.sh"
log_section "Check: hardening de container (root, limites, privilégios)"

DOCKERFILES=""
for f in Dockerfile Dockerfile.prod Dockerfile.production docker/Dockerfile build/Dockerfile; do
  [ -f "$f" ] && DOCKERFILES="$DOCKERFILES $f"
done
COMPOSES=""
for f in docker-compose.yml docker-compose.yaml compose.yml compose.yaml \
         docker-compose.prod.yml docker-compose.production.yml; do
  [ -f "$f" ] && COMPOSES="$COMPOSES $f"
done

if [ -z "$DOCKERFILES" ] && [ -z "$COMPOSES" ]; then
  log_info "sem Dockerfile nem compose — não se aplica"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

# ─── 1. USER: o container roda como root? ───
for df in $DOCKERFILES; do
  if grep -qE '^[[:space:]]*USER[[:space:]]+' "$df" 2>/dev/null; then
    ULT=$(grep -nE '^[[:space:]]*USER[[:space:]]+' "$df" | tail -1)
    LN=$(printf '%s' "$ULT" | cut -d: -f1)
    VAL=$(printf '%s' "$ULT" | sed -E 's/^[0-9]+:[[:space:]]*USER[[:space:]]+//' | tr -d '\r')
    case "$VAL" in
      root|0|root:*|0:*)
        add_finding "high" "Dockerfile declara USER $VAL — o container roda como root. Uma escrita arbitrária dentro do app vira escrita em todo o rootfs, e a distância até o host encurta." "$df" "$LN" ;;
      *)
        log_pass "$df roda como usuário não-root ($VAL)" ;;
    esac
  else
    LNF=$(grep -nE '^[[:space:]]*FROM[[:space:]]' "$df" | head -1 | cut -d: -f1)
    add_finding "high" "Dockerfile sem diretiva USER — o processo roda como root (uid 0) dentro do container. Adicione um usuário sem privilégio e um USER antes do CMD." "$df" "${LNF:-1}"
  fi
done

# ─── 2. Limites de CPU/memória no compose ───
# Um tenant sem teto faminta os vizinhos. Numa VPS compartilhada, o serviço que
# cai não é o que vazou memória — é o do lado.
for cp in $COMPOSES; do
  if grep -qE '(mem_limit|memory:|cpus:|cpu_quota|deploy:)' "$cp" 2>/dev/null; then
    grep -qE '(mem_limit|memory:)' "$cp" 2>/dev/null || \
      add_finding "med" "compose com bloco de recursos mas SEM teto de memória (mem_limit ou deploy.resources.limits.memory) — vazamento de memória aqui derruba os vizinhos do host, não este serviço" "$cp" ""
    grep -qE '(cpus:|cpu_quota|cpu_count)' "$cp" 2>/dev/null || \
      add_finding "low" "compose sem teto de CPU (cpus / deploy.resources.limits.cpus) — um laço quente aqui deixa o host inteiro lento" "$cp" ""
  else
    add_finding "med" "compose sem NENHUM limite de recurso (mem_limit, cpus, deploy.resources.limits) — o container pode consumir toda a máquina; numa VPS com vizinhos, quem cai é o serviço do lado" "$cp" ""
  fi

  # ─── 3. Privilégios ───
  grep -qE 'privileged:[[:space:]]*true' "$cp" 2>/dev/null && \
    add_finding "high" "compose com privileged: true — o container tem acesso praticamente equivalente ao host; só se justifica em runtime de infra, nunca num serviço de aplicação" "$cp" "$(grep -nE 'privileged:[[:space:]]*true' "$cp" | head -1 | cut -d: -f1)"
  grep -qE 'no-new-privileges' "$cp" 2>/dev/null || \
    add_finding "low" "compose sem security_opt: no-new-privileges:true — um binário setuid dentro da imagem consegue escalar privilégio" "$cp" ""
  grep -qE 'cap_drop' "$cp" 2>/dev/null || \
    add_finding "low" "compose sem cap_drop — o container carrega capabilities do kernel que um serviço web não usa (NET_RAW, MKNOD, SYS_CHROOT)" "$cp" ""
  grep -qE 'read_only:[[:space:]]*true' "$cp" 2>/dev/null || \
    add_finding "low" "compose sem read_only: true no rootfs — malware persistido dentro do container sobrevive ao restart" "$cp" ""
done

if [ "${#FINDINGS[@]}" -gt 0 ]; then
  case "${FINDINGS[*]}" in
    *'"severity":"high"'*|*'"severity":"crit"'*) emit_result "$BLINDAR_AGENT" "failed" 1; exit 1 ;;
  esac
  emit_result "$BLINDAR_AGENT" "failed" 0
  exit 0
fi

log_pass "container sem root, com teto de recurso e privilégio reduzido"
emit_result "$BLINDAR_AGENT" "passed" 0
exit 0
