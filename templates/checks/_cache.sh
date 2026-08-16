#!/usr/bin/env bash
# Cache de VEREDITO — guarda o resultado de um agente indexado pelo que ele
# analisou. Mesma evidência + mesmo agente + mesma versão = mesmo veredito, e a
# segunda rodada não paga API nem espera.
#
# NÃO confundir com o prompt caching da API (`cache_control: ephemeral`), que dá
# desconto dentro do mesmo request. Este evita o request inteiro.
#
# Onde dói: num projeto real foram 52 agentes deferred e 14 API-wrapped. Se o
# arquivo não mudou, o veredito não mudou — e hoje tudo é recalculado do zero.
#
# ─── AS TRÊS TRAVAS ───
# Cache que devolve resultado velho como se fosse novo é exatamente "ausência de
# medição virando aprovação", que é a família de bug que este projeto passou a
# sessão inteira corrigindo. Por isso:
#
#   1. O hash cobre a EVIDÊNCIA INTEIRA que foi enviada, não o nome do arquivo.
#      Conteúdo mudou → hash muda → cache não bate.
#   2. Cobre a VERSÃO do blindar e o SYSTEM PROMPT do agente. Agente corrigido
#      invalida veredito antigo, que foi produzido por outra lógica — senão uma
#      correção de check nunca chegaria a quem já tinha rodado.
#   3. O result reusado carrega `from_cache: true` e o `cached_at` original. O
#      relatório nunca apresenta reuso como medição nova.
#
# Desligar: BLINDAR_NO_CACHE=1

# Chave: sha256 dos quatro campos, separados por caractere que não aparece em
# nenhum deles. Usa Node porque sha256 em bash puro não existe de forma portátil.
blindar_cache_key() { # agente system_prompt conteudo → hash (ou vazio)
  [ "${BLINDAR_NO_CACHE:-0}" = "1" ] && return 0
  command -v node >/dev/null 2>&1 || return 0
  node -e '
    const c = require("crypto");
    const h = c.createHash("sha256");
    for (const parte of process.argv.slice(1)) { h.update(parte); h.update(""); }
    process.stdout.write(h.digest("hex").slice(0, 32));
  ' "$1" "${BLINDAR_SKILL_VERSION:-dev}" "$2" "$3" 2>/dev/null
}

blindar_cache_arquivo() { # agente hash → caminho
  printf '%s/cache/%s-%s.json' "${BLINDAR_DIR:-.blindar}" "$1" "$2"
}

# Tenta reusar. Sucesso (0) = gravou o result e o chamador deve retornar.
blindar_cache_try() { # agente hash
  local agente="$1" hash="$2"
  [ -z "${hash:-}" ] && return 1
  local arq; arq=$(blindar_cache_arquivo "$agente" "$hash")
  [ -f "$arq" ] || return 1
  command -v node >/dev/null 2>&1 || return 1
  mkdir -p "${RESULTS_DIR:-${BLINDAR_DIR:-.blindar}/results}"
  node -e '
    const fs = require("fs");
    const j = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    // O veredito é o mesmo; a PROCEDÊNCIA muda e precisa aparecer.
    j.from_cache = true;
    j.cached_at = j.ran_at;
    j.ran_at = new Date().toISOString().replace(/\.\d{3}/, "");
    fs.writeFileSync(process.argv[2], JSON.stringify(j, null, 2) + "\n");
  ' "$arq" "${RESULTS_DIR:-${BLINDAR_DIR:-.blindar}/results}/${agente}.json" 2>/dev/null || return 1
  return 0
}

# Guarda o result recém-produzido. Só o que foi MEDIDO entra: `skipped` por
# ferramenta ausente não é veredito, é ausência dele — cachear isso congelaria a
# lacuna e ela nunca mais seria reavaliada.
blindar_cache_store() { # agente hash
  local agente="$1" hash="$2"
  [ -z "${hash:-}" ] && return 0
  local origem="${RESULTS_DIR:-${BLINDAR_DIR:-.blindar}/results}/${agente}.json"
  [ -s "$origem" ] || return 0
  command -v node >/dev/null 2>&1 || return 0
  local arq; arq=$(blindar_cache_arquivo "$agente" "$hash")
  mkdir -p "$(dirname "$arq")"
  node -e '
    const fs = require("fs");
    let j;
    try { j = JSON.parse(fs.readFileSync(process.argv[1], "utf8")); } catch (e) { process.exit(0); }
    if (j.status === "skipped" || j.missing_tool) process.exit(0);
    delete j.from_cache; delete j.cached_at;
    fs.writeFileSync(process.argv[2], JSON.stringify(j, null, 2) + "\n");
  ' "$origem" "$arq" 2>/dev/null || true
}
