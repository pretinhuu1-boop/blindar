#!/usr/bin/env bash
# Materializa: pii-in-logs — dado pessoal indo parar no arquivo de log.
#
# Log é o lugar onde dado pessoal vaza sem que ninguém tenha decidido nada. Ele
# sai da aplicação, entra no agregador (Datadog, CloudWatch, Loki), é replicado,
# indexado, guardado por meses, e fica acessível a todo mundo que tem acesso ao
# painel de observabilidade — que é um grupo bem maior do que quem tem acesso ao
# banco. Para a LGPD isso é tratamento, com todas as obrigações que vêm junto.
#
# O caso mais comum não é logar `user.cpf` de propósito: é `logger.info(req.body)`
# no handler de cadastro. O objeto inteiro vai, com senha, CPF e cartão.
#
# Divisão com o check-observability: lá há uma regra pontual de PII em log. Aqui
# é a varredura completa — objeto inteiro, cabeçalho de autorização, nomes de
# campo em português — e cada achado sai com arquivo e linha.
BLINDAR_AGENT="check-pii-in-logs"
source "$(dirname "$0")/_lib.sh"
log_section "Check: PII em log (LGPD art. 6 / GDPR art. 5)"

if ! scan_hit 'console\.(log|info|warn|error|debug)|logger\.|log\.(info|warn|error|debug)|print\(|fmt\.Print|puts '; then
  log_info "nenhuma chamada de log encontrada — não se aplica"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
fi

LOGCALL='(console\.(log|info|warn|error|debug)|logger\.(info|warn|error|debug|trace)|log\.(info|warn|error|debug)|logging\.(info|warning|error|debug)|print|fmt\.Print(f|ln)?)'
IGN='(test|spec|mock|fixture|example|__tests__|\.d\.ts)'

# ─── 1. Campo de PII citado direto na chamada de log ───
#
# O termo sozinho não basta, e a versão ingênua deste check provou isso num
# projeto real: `console.warn('re-hash da senha falhou:', e.message)` virava
# achado (a palavra "senha" aparece numa frase, não um valor), e `larg` — nome
# de variável de largura de coluna — casava com `rg\b`. Dezessete achados, quase
# todos falsos. Falso-positivo em massa treina quem lê a ignorar o check inteiro,
# que é o oposto do objetivo.
#
# Agora o termo só conta quando aparece na FORMA de dado, não de prosa:
#   A) acesso a propriedade      user.cpf   obj["senha"]   dados?.telefone
#   B) interpolação              `cpf=${cpf}`   f"...{cpf}"   %(cpf)s
#   C) chave de objeto literal   logger.info({ cpf, nome })   { senha: x }
CAMPOS='cpf|cnpj|senha|password|passwd|cvv|cvc|card_?number|numero_?cartao|credit_?card|ssn|passport|passaporte|telefone|phone_?number|whatsapp|endereco|endereço|cep|birth_?date|data_?nascimento|full_?name|nome_?completo|email'
FORMA="([.\\[][\"']?($CAMPOS)\\b|\\\$\\{[^}]*\\b($CAMPOS)\\b|%\\(?($CAMPOS)\\)?s|\\{[^}]*\\b($CAMPOS)[[:space:]]*[:,}])"
while IFS=: read -r file ln resto; do
  [ -z "${file:-}" ] && continue
  printf '%s' "$file" | grep -qEi "$IGN" && continue
  add_finding "high" "Log imprime campo de dado pessoal: $(trim_ws "$(printf '%.140s' "$resto")")" "$file" "$ln"
done <<EOT
$(scan_src "$LOGCALL[^;]*$FORMA" | head -25)
EOT

# ─── 2. Objeto inteiro da requisição ───
# `logger.info(req.body)` no cadastro despeja senha, CPF e cartão de uma vez.
# É o caminho mais curto entre "funciona" e "vazou".
while IFS=: read -r file ln resto; do
  [ -z "${file:-}" ] && continue
  printf '%s' "$file" | grep -qEi "$IGN" && continue
  add_finding "high" "Log despeja o objeto inteiro da requisição/usuário — o que vai junto é tudo que o cliente mandou, inclusive o que ninguém decidiu guardar: $(trim_ws "$(printf '%.140s' "$resto")")" "$file" "$ln"
done <<EOT
$(scan_src "$LOGCALL\([^)]*(req\.body|request\.body|req\.query|\breq\b[[:space:]]*\)|JSON\.stringify\((req|user|customer|cliente|payload)\)|\{[[:space:]]*user[[:space:]]*\}|\bctx\.request\.body)" | head -15)
EOT

# ─── 3. Credencial de sessão ───
while IFS=: read -r file ln resto; do
  [ -z "${file:-}" ] && continue
  printf '%s' "$file" | grep -qEi "$IGN" && continue
  add_finding "crit" "Log imprime credencial de sessão (Authorization/cookie/apiKey) — quem lê o painel de log passa a poder se autenticar como o usuário: $(trim_ws "$(printf '%.140s' "$resto")")" "$file" "$ln"
done <<EOT
$(scan_src "$LOGCALL[^;]*([.\[][\"']?(authorization|cookie|set-cookie|api_?key|apiKey|access_?token|refresh_?token|bearer)\b|\\\$\{[^}]*\b(authorization|cookie|api_?key|apiKey|access_?token|refresh_?token)\b|\{[^}]*\b(authorization|cookie|api_?key|apiKey|access_?token|refresh_?token)[[:space:]]*[:,}]|req\.headers[^.[])" | head -15)
EOT

if [ "${#FINDINGS[@]}" -gt 0 ]; then
  log_fail "${#FINDINGS[@]} chamada(s) de log com dado pessoal ou credencial"
  emit_result "$BLINDAR_AGENT" "failed" 1
  exit 1
fi

log_pass "nenhuma chamada de log despejando PII ou credencial"
emit_result "$BLINDAR_AGENT" "passed" 0
exit 0
