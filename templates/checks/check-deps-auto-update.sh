#!/usr/bin/env bash
# Materializa: deps-auto-update — a dívida de CVE só aparece em auditoria tardia.
#
# Sem monitoramento contínuo, ninguém descobre que uma dependência ficou
# vulnerável: descobre-se que ela ficou vulnerável HÁ DEZOITO MESES, no dia em
# que alguém finalmente roda um scanner. Aí não é mais atualizar um pacote — é
# atravessar dez versões maiores de uma vez, com quebra de API em cada uma.
#
# Foi exatamente o caso do Electron 34 → 44 numa auditoria real: 48 CVEs
# acumulados, e a correção deixou de ser um `npm update` para virar um projeto.
# O custo de atualizar cresce mais rápido que o intervalo entre atualizações.
BLINDAR_AGENT="check-deps-auto-update"
source "$(dirname "$0")/_lib.sh"
log_section "Check: atualização automática de dependências (Dependabot/Renovate)"

TEM_DEPS=0
for f in package.json requirements.txt pyproject.toml Pipfile go.mod Cargo.toml \
         Gemfile composer.json pom.xml build.gradle; do
  [ -f "$f" ] && TEM_DEPS=1
done
if [ "$TEM_DEPS" -eq 0 ]; then
  log_info "sem manifesto de dependências — não se aplica"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

CONFIG=""
for f in .github/dependabot.yml .github/dependabot.yaml dependabot.yml \
         renovate.json renovate.json5 .renovaterc .renovaterc.json \
         .github/renovate.json .gitlab/renovate.json; do
  [ -f "$f" ] && { CONFIG="$f"; break; }
done
# Renovate embutido no package.json também vale.
if [ -z "$CONFIG" ] && [ -f "package.json" ]; then
  grep -qE '"renovate"[[:space:]]*:' package.json 2>/dev/null && CONFIG="package.json"
fi
# GitLab/outros CI rodando renovate ou mend como job agendado.
if [ -z "$CONFIG" ]; then
  for f in .gitlab-ci.yml .gitlab-ci.yaml; do
    [ -f "$f" ] || continue
    grep -qiE 'renovate|mend' "$f" 2>/dev/null && { CONFIG="$f"; break; }
  done
fi

if [ -z "$CONFIG" ]; then
  add_finding "med" \
    "Sem .github/dependabot.yml e sem renovate.json — nenhuma atualização automática de dependências. A dívida de CVE não é descoberta: ela é acumulada em silêncio até a próxima auditoria manual, quando atualizar deixou de ser um comando e virou um projeto (dez versões maiores de uma vez, quebra de API em cada)." \
    ".github/dependabot.yml" ""
else
  log_pass "atualização automática configurada em $CONFIG"
  # Config existe mas cobre só um ecossistema num projeto poliglota, ou está
  # desligada. Config presente e inerte é pior que ausente: some da lista.
  if [ "$CONFIG" = ".github/dependabot.yml" ] || [ "$CONFIG" = ".github/dependabot.yaml" ]; then
    grep -qE '^[[:space:]]*-?[[:space:]]*package-ecosystem:' "$CONFIG" 2>/dev/null || \
      add_finding "med" "dependabot.yml sem nenhum 'package-ecosystem' declarado — o arquivo existe e não monitora nada; config inerte some da lista de pendências e o verde vira mentira" "$CONFIG" ""
    grep -qE '^[[:space:]]*(interval|schedule):' "$CONFIG" 2>/dev/null || \
      add_finding "low" "dependabot.yml sem 'schedule.interval' — sem cadência definida, a checagem fica a critério do padrão do provedor" "$CONFIG" ""
  fi
fi

if [ "${#FINDINGS[@]}" -gt 0 ]; then
  emit_result "$BLINDAR_AGENT" "failed" 0
  exit 0
fi
emit_result "$BLINDAR_AGENT" "passed" 0
exit 0
