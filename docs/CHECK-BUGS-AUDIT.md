# Auditoria dos checks determinísticos — bugs sistêmicos (2026-07-04)

> **Descoberta crítica.** Ao tentar adicionar cobertura de teste aos 64 checks
> determinísticos (`templates/checks/check-*.sh`), foram encontrados **bugs
> sistêmicos** que fazem vários checks retornarem "nada encontrado" (falso
> negativo silencioso) — o pior tipo de falha num scanner de segurança:
> ele diz "verde" quando devia gritar.
>
> Status: **CORRIGIDO no motor (v0.45.0)** — ver "Resolução" abaixo. O
> fallback `rg` de `_lib.sh` foi reescrito com fidelidade ao ripgrep, um
> transform seguro (`scripts/fix-check-syntax.js`) corrigiu 55/77 checks pra
> ambientes com ripgrep real, e um gate (`scripts/check-selftest.sh`) prova
> por par de fixture que o check dispara-no-vulnerável e cala-no-limpo.

## Resolução (v0.45.0 — 2026-07-04)

1. **`_lib.sh` — fallback `rg` reescrito.** Flags agrupados (`-cE`, `-nE`,
   `-lE`, `-niE`, `-hoE`) agora normalizados char-a-char (`E` é no-op); `-c`
   filtra `:0` (conta só arquivos com match, igual `rg -c`, não `grep -rc`);
   `-n` preservado (antes era descartado → quebrava `IFS=: read file line`);
   excludes default (node_modules/.git/dist/.blindar). Fim do falso-negativo
   silencioso no ambiente atual (Windows/Git Bash, onde `rg` não é binário).
2. **`scripts/fix-check-syntax.js` — transform SEGURO** (tokeniza flags, nunca
   toca dentro de strings de padrão; NÃO é sed cego). Aplicado a 55/77 checks:
   `rg -E`→`rg`, `IGNORE=('!x')`→`IGNORE=(-g '!x')`, `grep -c … || echo 0`→
   `grep -c …`. Corrige o caminho com ripgrep real (CI/macOS/Linux).
3. **`scripts/check-selftest.sh` — gate meta.** Pares vuln/limpo verificados;
   cobertura honesta reportada (7/77 no commit inicial). Já pegou 1
   falso-positivo real (`check-prisma-schema` na fixture boa → faltava
   `/// @blindar:global` no `AuditLog`).
4. **CI (`lint.yml`)** roda o self-test com ripgrep real E com fallback grep —
   os dois DEVEM dar o mesmo veredito.
5. **Fixtures higienizadas**: `project-insecure-api` ganhou rota IDOR
   (`req.params.id` sem ownership); `project-prisma-good` anota `AuditLog`.

**Restam ~70 checks sem par de fixture** (cobertura 9%). O motor está são; o
que falta é o trabalho incremental de escrever um par por check — agora
destravado e forçado pelo gate. Todo check novo entra em `PAIRS` antes de mergear.

---

## Contexto: o gap que revelou os bugs

- **64 checks determinísticos**, mas só **4 fixtures** provavam algum.
- 60 checks nunca foram validados contra um projeto vulnerável real.
- Ao construir fixtures (fire-on-vulnerable + quiet-on-clean), os checks
  falharam em detectar vulnerabilidades plantadas.

---

## Bug 1 — `rg -E` interpretado como `--encoding` (39 checks, 148 ocorrências)

ripgrep **não** usa `-E` pra "extended regex" (ele já é ERE por padrão).
`-E` é `--encoding`. Então `rg -cE "pat"` vira `rg -c --encoding "pat"` → erro.

```bash
$ rg -cE "(app\.(post|put|delete))" --type ts
rg: error parsing flag -E: unknown encoding: (app\.(post|put|delete))
$ echo $?
2
```

Com `2>/dev/null || echo 0` no check, o erro é engolido → variável = 0 →
**check passa sem detectar nada.**

**Fix:** `rg -cE` → `rg -c`, `-nE` → `-n`, `-lE` → `-l`, `-hoE` → `-ho`, etc.
(remover o `E`). Ocorrências: `-cE`(20) `-ciE`(2) `-hoE`(3) `-lE`(54)
`-nE`(66) `-niE`(3).

## Bug 2 — IGNORE passado como path posicional, não `-g` (36 checks)

```bash
IGNORE=('!node_modules' '!dist' '!**/*.test.*')
rg -c "pat" --type ts "${IGNORE[@]}"   # ← ERRADO
```

`'!node_modules'` vira um **path posicional** que o rg tenta abrir — não
existe → 0 resultados. Prova:

```bash
$ rg -c "app\.(post|put|delete)" --type ts '!node_modules' | wc -l
0                                    # ← path posicional (bug)
$ rg -c "app\.(post|put|delete)" --type ts -g '!node_modules' | wc -l
1                                    # ← -g correto
```

**Fix:** `IGNORE=(-g '!node_modules' -g '!dist' ...)` e manter `"${IGNORE[@]}"`.

## Bug 3 — `grep -c ... || echo 0` gera saída dupla (30 checks)

`grep -c` já imprime um número (0 se nada) mas **sai com código 1** quando
não há match — aí `|| echo 0` dispara e imprime OUTRO "0":

```bash
$ X=$(grep -c "pat" arquivo-sem-match || echo 0); echo "[$X]"
[0
0]                                   # ← "0\n0"
$ [ "$X" -eq 0 ] && echo ok
bash: [: 0\n0: integer expression expected   # ← quebra a comparação
```

Comparação quebrada → o `-eq`/`-gt` falha → check não marca o finding → passa.

**Fix:** remover ` || echo 0` após `grep -c` (o `grep -c` já emite "0"; sem
`set -e` o exit 1 é inofensivo).

## Bug 4 (secundário) — `rg -c | wc -l` conta arquivos, não matches

`rg -c` imprime `arquivo:contagem` (1 linha por arquivo). `| wc -l` conta
**arquivos com match**, não o total de ocorrências. Em vários checks o intuito
era contar ocorrências. Revisar caso a caso.

---

## Impacto

Combinados, bugs 1+2 fazem a maioria dos checks **rg-based** (a maior parte dos
64) retornar 0 → **passam sem detectar**. A "camada determinística / ground
truth" — o principal diferencial do blindar sobre um LLM — está parcialmente
cega. Um `.env` exposto ou rota sem rate-limit pode não ser pego.

Verificado empiricamente:
- `check-cors-csrf` detecta CORS `*` **só depois** do fix de bugs 1+2.
- `check-rate-limit`, `check-headers-security`, `check-soft-delete`,
  `check-audit-log` **não** falham em fixture vulnerável no estado atual.

## Fixtures de prova (já no repo)

- `tests/fixtures/project-insecure-api/` — CORS `*`, rotas sem rate-limit,
  sem headers de segurança. **Deve** falhar cors-csrf/rate-limit/headers.
- `tests/fixtures/project-secure-api/` — helmet, rate-limit, CORS específico.
  **Deve** passar.
- `tests/fixtures/project-prisma-good/` — deletedAt + AuditLog + tenantId.
  **Deve** passar soft-delete/audit-log.

## Plano de correção (passe dedicado, verificado)

Não fazer sed cego no núcleo de segurança. Por check crítico:

1. Aplicar fixes 1–3 (mecânicos, seguros individualmente).
2. Rodar contra fixture vulnerável → confirmar exit 1.
3. Rodar contra fixture limpa → confirmar exit 0.
4. Só então adicionar `TEST_CASE` em `tests/run-tests.sh`.
5. Repetir pros 64. Priorizar os de severidade crítica primeiro
   (secrets, access-control, injection, cors, rate-limit, headers, crypto).

Meta: nenhum check sem par de fixtures (vulnerável+limpa) provando que
detecta o que promete. **Volume sem verificação = falso senso de segurança.**

---

## Notas da tentativa de fix (2026-07-04) — por que exige passe dedicado

Aplicando os 3 fixes nos 5 checks críticos e verificando por fixture:

- ✅ `check-audit-log` — passou a funcionar (falha no bad, passa no good).
- ✅ `check-cors-csrf` — passou a **detectar** CORS `*` (antes não detectava).
- ⚠️ Surpresas por check que impedem fix mecânico cego:
  1. **Contaminação de fixture por comentário.** Checks keyword-based (`rg`)
     casam palavras nos **comentários** da fixture (ex: `// rate-limit: ...`).
     Fixtures precisam de comentários neutros.
  2. **Estado oculto / não-determinismo.** `check-rate-limit` reportou
     `HAS_RL=1` num fixture onde o comando `rg` idêntico rodado à mão retorna
     `0`. Há estado residual (provável `.blindar/results/*` de runs anteriores
     interferindo, ou ordem de execução) que precisa isolamento por check.
  3. **Falso-positivo latente.** `check-cors-csrf` passou a falhar no fixture
     **limpo** também — precisa ajuste fino do regex/fixture.

**Conclusão:** o fix é real e direcionalmente correto, mas cada check tem
comportamento próprio que exige depuração isolada + fixture higienizada +
limpeza de estado entre runs. Não é sed cego. Estimativa realista: um passe
metódico dedicado (não uma sessão junto de outras tarefas).

Estado atual: checks mantidos em v0.44 (intactos). Bugs documentados e
fixtures de prova commitados pra destravar o passe futuro.
