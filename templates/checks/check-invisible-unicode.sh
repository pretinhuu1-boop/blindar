#!/usr/bin/env bash
# Materializa: invisible-unicode — caractere que você não vê, e que muda o que
# o código faz ou o que a pessoa lê.
#
# Não é higiene de texto: são três vetores de ataque publicados.
#
#   1. TROJAN SOURCE (CVE-2021-42574). Controles bidi de override/embedding
#      fazem o arquivo RENDERIZAR diferente do que COMPILA. Você revisa uma
#      coisa e mergeia outra — e o diff no GitHub mostra a versão renderizada.
#   2. CONTRABANDO PARA LLM. Tag chars U+E0020–E007F são invisíveis em qualquer
#      editor e chegam intactos ao modelo. É carregador de prompt injection que
#      nenhuma revisão humana pega.
#   3. HOMÓGLIFO. А В Е К М Н О Р С Т Х cirílicos são indistinguíveis das
#      latinas. Serve para spoofing de domínio e de identificador.
#
# E o efeito comum: zero-width em texto de usuário quebra busca, LIKE no banco,
# copiar-colar e leitor de tela.
#
# A detecção vai em Node porque o que separa achado de ruído é CONTEXTO, e
# contexto não cabe em regex: ZWJ/ZWNJ são ortografia legítima em persa e
# devanágari; ZWJ depois de emoji é parte do glifo visível; bandeiras usam tag
# chars de propósito; e marca direcional é válida em prosa RTL misturada. Um
# check que remove "tudo que é invisível" quebra persa, emoji e árabe.
#
# O JS abaixo NÃO pode conter aspa simples — ele vive dentro de node -e Aspas.
BLINDAR_AGENT="check-invisible-unicode"
source "$(dirname "$0")/_lib.sh"
log_section "Check: Unicode invisível (Trojan Source, contrabando, homóglifo)"

command -v node >/dev/null 2>&1 || {
  BLINDAR_MISSING_TOOL="node"
  log_warn "node ausente — a detecção exige contexto, que não cabe em regex"
  emit_result "$BLINDAR_AGENT" "skipped" 0
  exit 0
}

SAIDA=$(mktemp)

# Saída em TSV, não JSON. O parsing em bash era por sed, e a mensagem legítima
# contém aspas — o escape do JSON quebrava a extração e o achado sumia. Tab é
# separador seguro porque a mensagem nunca contém tab.
node -e '
const fs = require("fs"), path = require("path");
const raiz = process.argv[1];

const PULAR = new Set(["node_modules",".git","dist","build",".next",".nuxt","out",
  "coverage","vendor",".svelte-kit",".turbo","venv",".venv","__pycache__"]);
const TEXTO = /\.(ts|tsx|js|jsx|mjs|cjs|py|go|rs|java|rb|php|cs|swift|kt|c|h|cpp|sql|sh|yml|yaml|json|md|html|css|scss|txt|prisma)$/i;
const CODIGO = /\.(ts|tsx|js|jsx|mjs|cjs|py|go|rs|java|rb|php|cs|swift|kt|c|h|cpp|sql|sh|prisma)$/i;

const BIDI_DESTRUTIVO = new Set([0x202A,0x202B,0x202C,0x202D,0x202E]);
const BIDI_ISOLADOR   = new Set([0x2066,0x2067,0x2068,0x2069]);
const ZERO_WIDTH      = new Set([0x200B,0xFEFF,0x2060,0x180E]);
const JUNTOR_ESCRITA  = new Set([0x200C,0x200D]);
const ESPACO_EXOTICO  = new Set([0x00A0,0x2000,0x2001,0x2002,0x2003,0x2004,0x2005,
  0x2006,0x2007,0x2008,0x2009,0x200A,0x202F,0x205F,0x3000]);
const HIFEN_SUAVE = 0x00AD;

const HOMOGLIFO = new Map([[0x0410,"A"],[0x0412,"B"],[0x0415,"E"],[0x041A,"K"],[0x041C,"M"],
  [0x041D,"H"],[0x041E,"O"],[0x0420,"P"],[0x0421,"C"],[0x0422,"T"],[0x0425,"X"],
  [0x0430,"a"],[0x0435,"e"],[0x043E,"o"],[0x0440,"p"],[0x0441,"c"],[0x0443,"y"],
  [0x0445,"x"],[0x0456,"i"]]);

const ehEmojiBase = (cp) => cp !== undefined && (
  (cp >= 0x1F300 && cp <= 0x1FAFF) || (cp >= 0x2600 && cp <= 0x27BF) ||
  (cp >= 0x1F000 && cp <= 0x1F2FF) || cp === 0x00A9 || cp === 0x00AE);
const ehEscritaJuntora = (cp) => cp !== undefined && (
  (cp >= 0x0600 && cp <= 0x06FF) || (cp >= 0x0750 && cp <= 0x077F) ||
  (cp >= 0x0900 && cp <= 0x0DFF) || (cp >= 0x1000 && cp <= 0x109F));

const achados = [];
const emitir = (sev, arq, linha, msg) =>
  achados.push([sev, arq, String(linha), String(msg).replace(/[\t\r\n]+/g, " ")].join("\t"));

function varrer(arq, rel) {
  let txt;
  try { txt = fs.readFileSync(arq, "utf8"); } catch (e) { return; }
  if (txt.includes(String.fromCharCode(0))) return;
  if (txt.includes("@blindar:unicode-ok")) return;
  const cps = [...txt];
  const ehCodigo = CODIGO.test(arq);
  let linha = 1;
  const vistos = new Set();
  const jaVi = (k) => { const c = k + ":" + linha; if (vistos.has(c)) return true; vistos.add(c); return false; };
  const hex = (cp) => "U+" + cp.toString(16).toUpperCase();

  for (let i = 0; i < cps.length; i++) {
    const ch = cps[i], cp = ch.codePointAt(0);
    if (ch === "\n") { linha++; continue; }
    // Controles C0, exceto tab e CR, que são texto normal. Backspace, vertical
    // tab e form feed são invisíveis no editor igual aos de cima, e aparecem
    // por acidente quando um escape de outra linguagem é interpretado.
    // Encontrado no README deste próprio repositório: ao escrever o caminho
    // do Windows, `skills` + escape + `lindar` virou `skills` + backspace.
    if (cp < 0x20 && cp !== 0x09 && cp !== 0x0D) {
      if (!jaVi("c0")) emitir("high", rel, linha,
        "caractere de controle C0 " + hex(cp) + " — invisível no editor; costuma vir de escape interpretado por engano e corrompe a string em silêncio");
      continue;
    }
    if (cp < 0x80) continue;
    const ant = i > 0 ? cps[i-1].codePointAt(0) : undefined;

    if (BIDI_DESTRUTIVO.has(cp)) {
      if (!jaVi("bidi")) emitir("crit", rel, linha,
        "controle bidi " + hex(cp) + " reordena o texto: o arquivo RENDERIZA diferente do que COMPILA (Trojan Source, CVE-2021-42574) — a revisão vê uma coisa e o compilador outra");
      continue;
    }
    if (BIDI_ISOLADOR.has(cp) && ehCodigo) {
      if (!jaVi("bidiiso")) emitir("high", rel, linha,
        "isolador bidi " + hex(cp) + " em código-fonte — legítimo em prosa RTL, sem uso em código");
      continue;
    }
    if (ZERO_WIDTH.has(cp)) {
      if (i === 0 && cp === 0xFEFF) continue;
      if (!jaVi("zw")) emitir("high", rel, linha,
        "caractere de largura zero " + hex(cp) + " — invisível ao revisor; em texto de usuário quebra busca, LIKE no banco e copiar-colar");
      continue;
    }
    if (JUNTOR_ESCRITA.has(cp)) {
      const prox = i+1 < cps.length ? cps[i+1].codePointAt(0) : undefined;
      if (ehEmojiBase(ant) || ehEmojiBase(prox) || ehEscritaJuntora(ant) || ehEscritaJuntora(prox)) continue;
      if (!jaVi("zwj")) emitir("high", rel, linha,
        hex(cp) + " fora de contexto de emoji ou de escrita juntora — invisível, e nesta posição não é ortografia");
      continue;
    }
    if (cp >= 0xE0020 && cp <= 0xE007F) {
      let base = i - 1;
      while (base >= 0 && cps[base].codePointAt(0) >= 0xE0020 && cps[base].codePointAt(0) <= 0xE007F) base--;
      if (base >= 0 && cps[base].codePointAt(0) === 0x1F3F4) continue;
      if (!jaVi("tag")) emitir("high", rel, linha,
        "tag char " + hex(cp) + " — invisível em qualquer editor e chega intacto ao LLM; é carregador de prompt injection que revisão humana não pega");
      continue;
    }
    if (HOMOGLIFO.has(cp)) {
      const ehPalavra = (c) => c !== undefined && !/[\s\p{P}]/u.test(String.fromCodePoint(c));
      let ini = i, fim = i;
      while (ini > 0 && ehPalavra(cps[ini-1].codePointAt(0))) ini--;
      while (fim+1 < cps.length && ehPalavra(cps[fim+1].codePointAt(0))) fim++;
      const palavra = cps.slice(ini, fim+1).join("");
      if (!/[A-Za-z]/.test(palavra)) continue;
      if (!jaVi("homo")) emitir("high", rel, linha,
        "homóglifo cirílico " + hex(cp) + " (parece " + HOMOGLIFO.get(cp) + ") misturado com latino em " + palavra.slice(0,40) + " — indistinguível a olho, serve para spoofing de identificador e de domínio");
      continue;
    }
    if (cp === HIFEN_SUAVE && ehCodigo) {
      if (!jaVi("shy")) emitir("med", rel, linha,
        "hífen suave U+00AD em código — invisível, quebra comparação de string");
      continue;
    }
    if (ESPACO_EXOTICO.has(cp) && ehCodigo) {
      if (!jaVi("sp")) emitir("med", rel, linha,
        "espaço não-ASCII " + hex(cp) + " em código — parece espaço comum e não é; quebra parsing e comparação");
    }
  }
}

function andar(dir, rel) {
  let itens;
  try { itens = fs.readdirSync(dir, {withFileTypes:true}); } catch (e) { return; }
  for (const it of itens) {
    if (it.name.startsWith(".blindar")) continue;
    if (PULAR.has(it.name)) continue;
    const p = path.join(dir, it.name), r = rel ? rel + "/" + it.name : it.name;
    if (it.isDirectory()) andar(p, r);
    else if (TEXTO.test(it.name)) varrer(p, r);
  }
}
andar(raiz, "");
// Terminador OBRIGATÓRIO: o `while read` do bash descarta a última linha quando
// ela não termina em newline — sem isto, o último achado sumia em silêncio.
process.stdout.write(achados.length ? achados.join("\n") + "\n" : "");
' "." > "$SAIDA" 2>/dev/null || true

while IFS=$'\t' read -r sev arq ln msg; do
  [ -z "${sev:-}" ] && continue
  add_finding "$sev" "$msg" "$arq" "$ln"
done < "$SAIDA"
rm -f "$SAIDA"

if [ "${#FINDINGS[@]}" -gt 0 ]; then
  log_fail "${#FINDINGS[@]} caractere(s) invisível(is) com potencial de ataque"
  emit_result "$BLINDAR_AGENT" "failed" 1
  exit 1
fi

log_pass "nenhum Unicode invisível fora de contexto legítimo"
emit_result "$BLINDAR_AGENT" "passed" 0
exit 0
