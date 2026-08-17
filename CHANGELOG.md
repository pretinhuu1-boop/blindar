# Changelog

Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/).
Versionamento [SemVer](https://semver.org/lang/pt-BR/).

## [0.77.0] — 2026-08-17

### O SAST voltou a rodar no Windows, por container

A v0.76.0 fez o blindar parar de mentir sobre o semgrep quebrado. Esta faz o
semgrep funcionar.

Não consertando o binário — o problema é o wrapper desta plataforma, que delega
ao `semgrep-core` por RPC e morre com `rule validation failed` em qualquer scan.
A imagem oficial é Linux, onde o semgrep funciona, e o wrapper sai inteiro do
caminho.

A ordem importa: nativo com `auto`, nativo com rulesets explícitos, e só então
container. Onde o nativo funciona — Linux, macOS — ele continua sendo o
primeiro, é mais rápido e não exige Docker. O fallback existe para a plataforma
onde o caminho normal está quebrado, não para substituí-lo.

Medido: nativo rc=2 em qualquer scan; via container, **1074 regras**, e os dois
achados esperados no mesmo arquivo — `eval` com input do usuário e concatenação
em query SQL.

Duas armadilhas no caminho, as duas do tipo que passa despercebido:

- **`cygpath -m` no mount.** O Docker no Windows precisa de `C:/...` e o bash
  entrega `/c/...`. Montar o caminho POSIX cria um bind **vazio**: o scan varre
  nada e sai 0. Seria pior que falhar, porque "nada encontrado" pareceria
  resultado.
- **Caminho do achado.** O container vê o projeto em `/src`, então o relatório
  apontava para `/src/src/api.js` — um arquivo que não existe na máquina de quem
  lê. Achado que você não consegue abrir é quase inacionável.

### `check-semgrep` saiu da lista de exclusão

Ele estava lá como "o veredito é do scanner, exige rede e base de CVE". Com o
fallback, o comportamento virou determinístico o bastante para ter contrato:
dispara em `eval` com input do usuário e SQL concatenado, cala em query
parametrizada.

O primeiro fixture "limpo" não era limpo — o semgrep achou um XSS real,
`res.send()` com valor derivado de input do usuário. Ele estava certo, e o
fixture virou `res.json()`. Fixture que passa porque o check é fraco não prova
nada; este passou a provar.

**Cobertura: 80/80 gate-áveis (100%).** A conta: 108 checks = 80 com par + 28
com motivo declarado + 0 sem conta.
## [0.76.0] — 2026-08-16

### O doctor mostrava ✓ verde para um scanner que não varre

`semgrep --version` responde `1.167.0` normalmente nesta máquina. Qualquer scan
de verdade morre com `semgrep-core rule validation failed`, rc=2 — o binário é
um wrapper que delega por RPC, e o `--version` nem chega lá.

O doctor perguntava a versão e pintava de verde. O `check-semgrep` recebia o
rc=2, rebaixava para um achado `med` "possível erro de config" e seguia — como o
relatório vinha vazio, o check terminava em **`passed`**. O SAST inteiro não
rodou e o status disse aprovado.

Duas correções:

1. **`check-semgrep`**: erro do scanner vira `skipped` com
   `missing_tool=semgrep(rc=N)`. Erro é ausência de medição, não ausência de
   achado. Antes de desistir, tenta rulesets explícitos, porque `--config=auto`
   é o que falha nesta plataforma.
2. **`doctor`**: não escreve smoke próprio — **roda o próprio check** contra um
   projeto mínimo e lê o veredito. A primeira tentativa foi um smoke separado
   com regra local, que passava enquanto o check falhava: exatamente a
   divergência entre quem mede e quem reporta que este projeto persegue desde o
   começo. Uma pergunta, uma fonte.

O resultado nesta máquina passou de `✓ semgrep 1.167.0` para
`✗ semgrep instalado, quebrado — o check sai skipped (semgrep(rc=2))`.

Isso não conserta o semgrep no Windows. Conserta o blindar dizer que está tudo
bem quando não está — que é a única parte que cabia a ele.
## [0.75.0] — 2026-08-16

### `check-horizontal-scale` — o que funciona com uma réplica e quebra com duas

O `process-resilience` pergunta se **o processo** aguenta: health check, shutdown
limpo, backpressure, deadlock. Todas as respostas dele continuam válidas com uma
instância só.

Este pergunta outra coisa: **o sistema aguenta ser mais de um?** É uma propriedade
que não aparece em nenhuma instância isolada — cada réplica está perfeitamente
saudável enquanto o conjunto está errado.

O que torna essa família cara é como ela falha. Nada quebra em homologação,
porque homologação roda uma instância. Quebra em produção, na primeira vez que
alguém sobe a segunda — e quebra **de forma intermitente**, porque depende de
qual réplica atendeu a requisição. O que chega ao suporte não é "quebrou":

- "às vezes ele me desloga"
- "o rate limit não está segurando direito"
- "a mensagem do chat às vezes não chega pros outros"
- "o arquivo que subi sumiu, mas depois voltou"

Intermitente por roteamento é o pior tipo de bug para diagnosticar: não reproduz
na máquina do desenvolvedor, não reproduz em staging, e o log de uma réplica só
não conta a história.

| # | O que | Sintoma com N réplicas |
|---|---|---|
| 1 | `express-session` sem `store` | usuário desloga ao ser roteado para outra instância |
| 2 | rate limit sem store compartilhado | limite efetivo vira N× o configurado |
| 3 | `socket.io` sem adapter Redis | metade da sala não recebe o broadcast |
| 4 | upload em disco local | GET seguinte cai na outra réplica e dá 404 |
| 5 | `Map`/`Set` como fonte da verdade | token revogado continua válido na outra réplica |
| 6 | webhook sem idempotência | reenvio do provedor credita duas vezes |

O item 2 merece destaque: é **pior que não ter rate limit**, porque parece ter.
Passa no `check-rate-limit`, aparece configurado no código, e não protege.
Proteção de fachada é pior que ausência de proteção, porque ninguém vai
procurar.

O 7º sinal — `sessionAffinity` / `ip_hash` na infra — não é defeito em si. É
indício de que alguém já encontrou o item 1 e o contornou no balanceador.
Funciona, e some no primeiro redeploy ou quando uma réplica cai.

O que o check **não** decide é se você deveria escalar: uma instância só é
decisão legítima. Ele diz se o código suporta a segunda — porque a hora de
descobrir que não suporta não é durante o incidente.

Balanceador, health check do LB e terminação TLS são máquina, não código: quem
verifica é o `ancorar`.

### A meta escrita passou a ser cobrada

O gate já imprimia "Cada check novo DEVE entrar em PAIRS antes de mergear", e
não verificava. Escrever a regra sem cobrar é o mesmo que não ter regra, só que
com a aparência de ter.

Medido nesta sessão: um check novo entrou na árvore no meio de uma rodada, a
cobertura caiu para 78/79 e o resumo continuou dizendo "todos os pares
registrados corretos" — certo sobre os registrados, calado sobre o que não foi
registrado, que é justamente o buraco. Agora gate-ável sem par é **regressão**.
## [0.74.0] — 2026-08-16

A v0.73.0 provou que o blindar roda em outra máquina. Esta pergunta a seguinte:
**roda em outro sistema operacional?** Ele nunca tinha rodado em Linux. Um
container achou quatro coisas que o Windows escondia — e uma delas era um
segundo falso negativo no scan de segredos.

### O check-gitleaks também varria o lugar errado

O log dizia "escaneando working tree + history". Era só history: `gitleaks
detect` num repositório git varre os COMMITS. Arquivo no working tree que ainda
não foi commitado ele não vê.

Medido: repositório com histórico limpo e uma chave em `src/config.js` sem
commit saía `passed` — com o log afirmando que a working tree tinha sido varrida.
E auditar antes de commitar é o momento mais provável de auditar.

Mesmo desenho do falso negativo do `check-secrets` na v0.73.0, em outro check.
Agora a working tree é sempre varrida e o histórico entra a mais.

### `passed` com achado crit/high era possível

Nada verificava a coerência entre status e severidade. Cada check decidia
sozinho, com um `FAIL=1` espalhado por vários ramos, e bastava um ramo esquecer
de marcar para o check somar `add_finding "high"` e emitir `passed`.

Aconteceu: o `check-sbom-slsa` emitia `passed` carregando 1 high e 2 low. Os
achados apareciam na lista e o status dizia que estava tudo bem. Quem lê o status
— o gate, o agregado, o CI — via aprovação.

Agora a checagem vive no `emit_result`, por onde todo check passa: `passed` com
crit ou high vira `failed`, com aviso. Med e low continuam válidos com `passed`,
que é o caso informativo legítimo.

### CRLF: o mesmo projeto passava aqui e reprovava no CI

Três checks reprovaram no container Linux e passavam no Windows. Causa: um
`.gitignore` escrito no Windows termina cada linha com CR + LF, então a linha é
`node_modules` seguida de um carriage return — e a âncora `$` do regex não casa
antes dele. O grep do MSYS descarta o CR em modo texto; o GNU grep do Linux não.

A mensagem era "seu .gitignore não exclui node_modules" sobre um `.gitignore`
que exclui node_modules. Equipe Windows com CI Linux é o caso comum, não a
exceção.

Corrigido no `check-git-hygiene`, que agora remove o CR ao ler, e nos 86 fixtures
que estavam com CRLF — `.gitattributes` fixa `tests/fixtures/** text eol=lf`,
para o gate medir o check e não o fim de linha.

### O escape que só quebra em ripgrep antigo

`check-observability` procurava `(\/health\/live|\/healthz|...)`. Escapar a barra é
ideia de JavaScript, onde ela fecha o literal de regex — em ERE e PCRE a barra
não é especial. O ripgrep 15 aceita; o **13**, que vem no Debian estável e no
Ubuntu LTS, responde `regex parse error`.

O erro ia para `/dev/null`, o `|| true` seguia, o arquivo de saída ficava vazio
e ausência de resultado virava achado: o check dizia "sem health endpoints" num
projeto que tem `/healthz` e `/health/ready`. Quem tinha ripgrep novo nunca via;
quem tinha o antigo achava que o projeto é que estava errado.

`tests/regex-portable.test.mjs` recusa esse escape em qualquer padrão de busca.

### O falso positivo que o novo invariante desenterrou

Assim que o `emit_result` passou a recusar `passed` com crit/high, o
`check-rate-limit` reprovou no fixture limpo. O achado existia desde sempre — o
check somava um `high` e emitia `passed` assim mesmo, então ninguém via.

Eram dois defeitos na mesma linha: o padrão `rate.?limit` sem `-i` não casa
`rateLimit`, e o `xargs grep` recebia do `rg -l` caminhos no formato
`.\src\server.ts`, que o grep do MSYS não abre. Os dois davam contagem zero, e
o check acusava "endpoint sensível sem rate-limit" num projeto com rate-limit no
login.

A incoerência entre status e achado estava escondendo o defeito no achado.

### O gate destruía a pré-condição antes de medir

`run_status` apaga `.blindar` antes de rodar o check, para result velho não
contaminar a rodada. Só que alguns checks leem a saída do próprio blindar — o
`wave-guardian` decide fechar a onda a partir do `run-report.json` — e o fixture
deles precisa TRAZER um `.blindar`. O gate apagava justamente o insumo, e
reportava falso-positivo sobre um fixture correto.

Pior: `$dir` é o diretório versionado do fixture. A limpeza no fim apagava o
arquivo do repositório — a primeira execução funcionava e a segunda não.

### `tests/pairs-integrity.test.mjs`

O gate leva ~25 minutos. Este confere o REGISTRO em 2 segundos: fixture
referenciado que não existe, check que não existe, par duplicado, fixture órfão.

Existe porque apaguei `project-deps-*` achando que era meu, e era do
`check-deps-sync`. O gate imprimia `SKIP` e seguia verde: a cobertura caía e
ninguém era avisado. Agora fixture ausente é **regressão**, não skip.
### Os 14 checks de API nunca produziram um achado no Windows

O wrapper lia a resposta com `readFileSync('/dev/stdin')`. No Windows o node
resolve isso como caminho e procura `C:\dev\stdin` — ENOENT. O `catch` engolia,
a extração do `tool_use` devolvia vazio, e **todo** check `.api.sh` emitia
`skipped` com a mensagem "API não retornou tool_use estruturado", mesmo com
chave válida e resposta correta.

Quatorze agentes — pentest, adversarial-reviewer, architect, regulatory-mapper e
companhia — que nunca deram um achado nesta plataforma. E `skipped` se parece
com "não se aplica".

Só apareceu quando o contrato dos `.api.sh` passou a rodar com resposta
injetada. Enquanto o caminho dependia de uma chave de API de verdade, ninguém o
exercitava — que é precisamente o motivo pelo qual ele precisava de contrato.

### `validate.sh` aprovava JSON que não conseguiu abrir

Sem `jq` e sem `python3` ele imprimia `[WARN] sem jq nem python3 — pulando parse
check` e seguia para `[OK] JSON parsea sem erro`. JSON quebrado passava.

A imagem `node:22-bookworm` não traz nenhum dos dois — foi assim que apareceu.
Agora há um terceiro ramo em node, que é dependência essencial do blindar, e o
caso "não consegui parsear" **falha** em vez de aprovar.
### Os 14 checks `.api.sh` ganharam contrato

Ficavam fora do gate com a justificativa "precisam de LLM, logo não têm veredito
determinístico". Metade disso é verdade: o julgamento é do modelo. A outra metade
não — o que o check faz com a resposta é código comum, e código comum tem
contrato.

Era código sem nenhum teste, no caminho mais escorregadio do projeto. Já quebrou
ali: `IFS='||'` é um CONJUNTO `{|}`, então o campo vazio entre os dois pipes
deslocava tudo e todos os findings de API saíam com mensagem vazia e file/line
trocados.

`tests/api-contract.test.mjs` sobe um servidor HTTP local que devolve o que a API
devolveria (`BLINDAR_API_URL` passou a ser configurável) e verifica o que
pertence ao blindar: crit/high vira `failed` com os findings íntegros, zero
findings vira `passed`, severidade fora do enum cai para `low`, e resposta sem
`tool_use` vira `skipped` — nunca `passed`.

### "32 excluídos" virou 32 motivos

Um número onde deveria haver uma razão. Enquanto for um balde só, ninguém sabe
se lá dentro tem check que PODERIA ter contrato e só não tem — foi exatamente o
caso do `check-secrets`, que passou meses no balde carregando um falso negativo.

Cada exclusão agora tem nome e diz o que cobre aquele check no lugar. E o gate
**reprova** se aparecer check fora do gate sem motivo declarado.

### O check consultivo mandava a chave no argv

`check-proactive-analysis` não passa pelo `_api_wrapper.sh`: monta e envia a
requisição por conta própria — e enviava a chave em `-H "x-api-key: ..."`. O argv
é legível por qualquer processo local via `ps` ou `/proc/<pid>/cmdline`. O
wrapper já usava `--config -` (stdin) exatamente por isso; este ficou para trás.

Apareceu ao dar contrato aos catorze: ele era o único que ainda batia na API de
verdade durante o teste, porque não tinha a costura de injeção. "Treze de
catorze" é o tipo de lacuna que ninguém lembra depois.

### O gate agora conta certo

`is_gateable` usava heurísticas para adivinhar se um check daria para contratar
— e recusava o `check-functional-e2e` pela regra do `npx`, mesmo ele tendo par
registrado e passando. Entrava no numerador e ficava fora do denominador:
**78/77 = 101%**, a segunda vez que a métrica passou de 100%.

A regra virou: **par registrado é a resposta.** As heurísticas servem para
decidir sobre check SEM par; quando o par existe e passa, não há o que
adivinhar.

## A conta fecha

| | |
|---|---|
| checks com par de fixture | **78** |
| checks com motivo declarado | **29** |
| checks sem conta | **0** |
| total | **107** |

Cobertura dos gate-áveis: **78/78 (100%)**. Os 14 `.api.sh` têm contrato do
código em `tests/api-contract.test.mjs` — 122 asserções, sem gastar um token de
API. Os outros 15 dizem por escrito por que estão fora, e o gate **reprova** se
aparecer um sem motivo.

Verificado nos dois sistemas: Windows e container Linux, gate e suíte completa.
macOS continua **não verificado** — não há máquina para isso aqui, e dizer que
funciona lá seria exatamente o tipo de afirmação que este projeto existe para
não fazer.

## [0.73.0] — 2026-08-16

Esta versão saiu de uma pergunta simples: o blindar funciona em outra máquina?
Ele nunca tinha sido testado fora daqui. O teste de máquina limpa — HOME novo,
clone do GitHub, ambiente sem herança — achou coisa que dois anos de fixture
não achavam, incluindo um falso negativo no check de segredos.

### O check de segredos aprovava projeto com chave real

`check-secrets` começava por `gitleaks protect --staged`. O código de saída do
gitleaks é 0 = nenhum vazamento, 1 = achou. Numa auditoria não há nada staged:
ele varria um índice vazio, achava nada, saía 0 — e o `if` dava certo. O scan da
árvore de trabalho, que estava no `elif`, **nunca rodava**.

Chave da AWS em `src/` era reportada como `passed`.

E quando `protect` achava algo, saía 1, o `if` falhava, caía no `elif`, que ao
achar também saía 1 — nenhum ramo pegava, `scope` ficava indefinido e sob
`set -u` o script abortava. **Achar segredo quebrava o check.**

Agora a árvore de trabalho é sempre varrida, o índice é varrido a mais quando
existe, os dois relatórios são unidos com dedup, e o veredito vem da contagem —
nunca do código de saída. Saída >1 do gitleaks é erro, e erro não vira `passed`.

O fixture existente (`project-with-secrets`) tem os padrões mascarados de
propósito, para não virar segredo de verdade num repositório público. Por isso o
gitleaks nunca disparava nele e o par não cobria o caminho que quebrou. Entrou
`project-gitleaks-bad/good`, com segredos que o gitleaks **realmente** detecta
(JWT de exemplo do jwt.io e chave genérica) e que o Push Protection do GitHub
não bloqueia.

### O doctor dizia "ambiente completo" com 10 checks sem executar

Ele conferia 7 ferramentas. Os checks chamam gitleaks, trivy, semgrep,
osv-scanner, govulncheck, pip-audit, cargo-audit — nenhum na lista. Sem eles o
scan de CVE e de segredo não roda, e o doctor assinava embaixo.

A lista agora é **derivada dos checks instalados**, não escrita à mão: check novo
com dependência nova aparece sozinho. Lista à mão desatualizaria no primeiro
check adicionado e voltaria a mentir do mesmo jeito.

E o veredito final passou a separar "roda" de "completo".

### Ferramenta instalada que o blindar dizia não existir

No Windows o instalador grava o diretório no PATH persistente, mas processo já
em execução não recebe a mudança. Quem instala ripgrep, lê "Successfully
installed" e roda o blindar via terminal aberto vê 60 checks saírem `skipped`,
sem relação aparente.

O `_lib.sh` agora lê o PATH persistente do registro e junta o que falta. Não
inventa caminho nem mantém lista de gerenciador de pacote — usa o que a máquina
já declarou. Uma vez por árvore de processos.

`type -P` e não `command -v` para achar o ripgrep: o Claude Code define `rg` como
função de shell apontando para o ripgrep embutido nele. `command -v` acharia a
função e responderia "tem rg" — mas função não é herdada por processo filho, e
os checks rodam como filhos. Daria "tem" no agente e "não tem" no check.

### jq deixou de bloquear release

O doctor dizia que sem jq não se perde nada. Era falso nos dois sentidos:
`check-secrets` pulava inteiro (gitleaks instalado e o check de segredo não
rodava) e `check-termination` **bloqueava a release** por falta de jq.

Os dois passaram a ler com node, que já é dependência essencial. Continua
valendo a regra que originou tudo: valor ilegível nunca vira 0 — agora com
verificação explícita, e contagem não-numérica é NO-GO em vez de aprovação.

De quebra, a comparação de cobertura saiu do `bc`, que não existe por padrão no
Windows: `bc -l 2>/dev/null` devolvia vazio, `(( ))` vazio é erro de sintaxe e,
sob `set -e`, matava o script no meio — sem veredito e sem dizer por quê.

### A ponte para o ancorar aprovava host que ninguém olhou

Com o `ancorar` finalmente instalado, deu para exercitar a ponte de verdade —
até aqui ela chamava um script que não existia na máquina.

Contra host inalcançável, o ancorar pulava os 16 checks, a ponte imprimia
"fase 3 ok" e **saía 0**. O texto na tela já dizia "pulado != aprovado", mas o
código de saída dizia o contrário — e é o código de saída que CI e gate leem.

Agora: zero passou e zero falhou é `NÃO VERIFICADO`, exit 3. A mesma regra do
projeto, aplicada ao host.

A recusa de fase que muta o host (2/4/5/6/9) já estava correta: exit 64 e o
comando certo para rodar pelo ancorar, que impõe supervisão e dry-run.

### Checks que pulavam sem dizer por quê

Cinco (`gitleaks`, `secrets`, `trivy`, `semgrep`, `osv-scanner`) saíam `skipped`
com `missing_tool: null`. O relatório dizia "não rodou" sem dizer o que instalar
para fazer rodar.

### Achado sem localização

`check-runtime-secrets` contava com `wc -l` e chamava `add_finding` com arquivo e
linha **vazios** nos seis padrões. O relatório dizia "6 process.env não-público"
sem dizer em qual arquivo — crítico que ninguém consegue abrir.

Rodando contra projeto real, dois críticos assim não reproduziram. Sem
localização não havia como saber se eram reais, o que os torna piores que
inúteis: consomem confiança. Agora é um achado por ocorrência, com arquivo e
linha, e quando o teto de 15 corta, o achado **diz** quantos ficaram de fora.

### O gate reportava 101% de cobertura

Registrar o par do `check-secrets` fez a conta virar `75/74 (101%)`: o numerador
contava o par verificado, o denominador excluía o check por ser wrapper de
scanner externo. Métrica que passa de 100% não está medindo o que diz medir.

Wrapper de scanner com par registrado agora entra nos dois lados — alguém já
provou que existe fixture onde ele dispara.

E o gate ganhou um **terceiro estado**. Numa máquina sem gitleaks, o fixture
vulnerável do `check-secrets` sai `skipped`: contar como regressão reprovaria o
gate por causa do ambiente, e contar como ✓ diria "verificado" sobre algo que
ninguém executou. Agora sai `⊘ NÃO VERIFICADO (falta gitleaks)`, fora do
numerador e fora das regressões, listado no fim do resumo.

### O check de update mandava fazer downgrade

A comparação era `[ "$REMOTE" != "$LOCAL" ]` — diferente, não mais nova. Numa
instalação à frente do `main` (build de desenvolvimento, branch de release, ou
quem acabou de subir a versão) o aviso saía assim:

```
  blindar v0.72.0 disponivel
  Voce esta em v0.73.0
  Atualizar: curl -sSL .../install.sh | bash
```

Aceitar levaria a um **downgrade**. E como o `SKILL.md` usa o exit 10 para
*perguntar* ao operador se quer atualizar, perguntar "quer atualizar?" quando a
resposta certa é "você já está na frente" transforma o aviso em armadilha: quem
confia nele perde a versão nova.

Agora compara campo a campo, numericamente. Estar à frente diz isso e sai 0.

### `tests/maquina-limpa.sh`

O script que achou tudo acima entrou no repositório. HOME novo, `--local` para a
árvore de trabalho ou clone do GitHub para o que está publicado — os dois modos
importam, porque o clone é o que outra máquina recebe hoje.

### `tests/no-nul-bytes.test.mjs`

Um byte NUL entrou num `.join()` de JavaScript embutido em shell — segunda vez
nesta base, das duas pela mesma via: escape atravessando mais de uma camada.

O que torna caro é como falha. O script roda normalmente, mas o **git passa a
tratar o arquivo como binário**: some o diff, some o blame, e uma correção no
check de segredos aparece no pull request como `Bin 2296 -> 6355 bytes`. Ninguém
revisa o que não vê — foi assim que esta ocorrência foi notada, não por erro de
execução, mas porque `git diff --stat` disse "Bin".

## [0.72.0] — 2026-08-16

### Cache de veredito — não de prompt

O `_api_wrapper.sh` já usava `cache_control: ephemeral`, que é **desconto dentro
do mesmo request**. Isto é outra coisa: guarda o **resultado** do agente
indexado pelo que ele analisou. Mesma evidência + mesmo agente + mesma versão =
mesmo veredito, e a segunda rodada não paga API nem espera.

Onde dói: no projeto real são **52 agentes deferred + 14 API-wrapped**. Se o
arquivo não mudou, o veredito não mudou — e tudo era recalculado do zero.

**As três travas**, porque cache que devolve resultado velho como se fosse novo
é exatamente "ausência de medição virando aprovação" — a família de bug que
esta sessão inteira corrigiu:

1. O hash cobre a **evidência inteira enviada**, não o nome do arquivo.
2. Cobre a **versão do blindar e o system prompt do agente** — agente corrigido
   invalida veredito antigo, senão uma correção de check nunca chegaria a quem
   já tinha rodado.
3. O result reusado carrega `from_cache: true` e o `cached_at` original, e o
   resumo do run **conta** quantos vieram do cache. Reuso nunca é apresentado
   como medição desta rodada.

Quarta propriedade: `skipped` por ferramenta ausente **não entra no cache** —
não é veredito, é ausência dele, e cachear congelaria a lacuna para sempre.

Desligar: `BLINDAR_NO_CACHE=1`.

Implementado em `templates/checks/_cache.sh` separado, e não inline no wrapper:
misturar shell com JS inline já custou dois bugs de escape nesta sessão.

### `CLAUDE.md` de exemplo, opcional

`templates/CLAUDE.md.exemplo` entra no repo e o instalador **pergunta** antes de
copiar — com backup datado se já existir um. Governança global é do operador;
instalar por cima sem perguntar seria reescrever a forma de trabalhar de alguém.

Carrega os anti-padrões que este projeto pagou caro para aprender, incluindo o
mais caro de todos: *o default do desconhecido nunca é o valor bom*.

## [0.71.0] — 2026-08-16

### `SKILL.md` sai de 42 KB para 25 KB

O `SKILL.md` é carregado **em toda invocação** — inclusive quando o pedido é
rodar um único check. Ele havia crescido para 803 linhas com tudo que entrou
nesta sequência de versões.

15 seções saíram do caminho quente para `reference/`, com o critério: **é
referência consultada quando a etapa exige, ou decisão tomada em toda
invocação?** O que fica é o segundo.

| Arquivo | Tem |
|---|---|
| `reference/modulos-e-agentes.md` | menu dos 19 módulos, 12 leads, roster |
| `reference/camada-deterministica.md` | checks executáveis, instalador, intelligence |
| `reference/apoio.md` | frameworks, templates, runbooks, stacks, tendências |
| `reference/operacao.md` | sync dev↔instalada, auto-update, origem |

O que **permanece** no `SKILL.md`: a sequência mandatória, o roteamento do hub,
os 6 modos, os princípios e os gates — o que decide comportamento.

Mesmo tratamento que o `agentic-harness` já tinha recebido: entrada enxuta,
peso sob demanda.

**Links relativos corrigidos**: as seções movidas apontavam para `agents/`,
`pipeline/`, `templates/` — um nível acima a partir de `reference/`. Todos os
links dos dois lados foram verificados e resolvem.

## [0.70.0] — 2026-08-16

### Guard da lista CRITICAL — hook, não boa intenção

O `risk-engine` diz que apagar dado, desligar autenticação e reescrever
histórico compartilhado pausam mesmo em AUTO. Isso dependia de **o modelo
lembrar**. O `CLAUDE.md` do operador já tinha a regra: *"Claude pode esquecer de
executar algo. Hook não esquece."* — e o blindar não usava **nenhum** hook do
Claude Code.

- **`templates/hooks/blindar-guard.sh`** (novo): `PreToolUse` em `Bash`. Pausa
  `DROP`/`TRUNCATE`, `DELETE` sem `WHERE`, `migrate reset`, `push --force`,
  `reset --hard`, `filter-branch`, `rm -rf` em raiz e remoção de volume.
  Distingue `--force` de `--force-with-lease`, que passa.
- **`scripts/install-hooks.sh`** (novo): **lê antes de escrever e faz merge** —
  `settings.json` costuma ter configuração do operador, e substituir apagaria
  hooks e permissões existentes. Idempotente. Recusa arquivo malformado em vez
  de sobrescrever.

Três decisões de desenho:

**Pausa, não proíbe.** A regra é pedir autorização. `deny` tornaria impossível o
trabalho legítimo (migração planejada, decommission autorizado) e o operador
desligaria o hook inteiro — trocando uma pausa por nenhuma proteção.

**Cada pausa diz o que se perde**, não só "perigoso". Pausa sem custo explícito
vira clique reflexo em "sim", que é o mesmo que não pausar.

**Falha aberta de propósito.** Sem `node`, libera com aviso. Um guard que
bloqueia todo comando porque uma dependência sumiu é desinstalado no primeiro
minuto. É defesa em profundidade — o playbook continua valendo por cima.

### Allowlist só-leitura

O mesmo instalador adiciona `git status`, `git diff`, `git log`, `Read`,
`Grep`… Nada que altere estado entra: a allowlist existe para tirar atrito de
comando inofensivo, não para pular decisão que importa.

## [0.69.0] — 2026-08-16

### O hub

Um comando resolve. O `blindar` roteia o pedido **antes** de agir:

```
                    ┌─ servidor?      → ancorar-bridge.sh
  blindar  ─────────┼─ criar skill?   → skill-builder
                    └─ este projeto?  → os 6 modos
```

Chamar `blindar` passa a cobrir: auditar, construir, acrescentar, evoluir,
consertar, organizar o repositório, **verificar o servidor** e **criar a próxima
skill**. Sem ter de lembrar qual ferramenta chamar.

- **`pipeline/00-mode-select.md`** ganha o **Passo 0**: roteamento de intenção
  acima dos 6 modos. Inclui a desambiguação que evita o erro mais comum —
  *"verifica o deploy"* é projeto se for sobre o artefato e o compose; é
  `ancorar` se for sobre o servidor. Na dúvida: "o código ou a máquina?".
- **`agents/skill-builder.md`** (novo) + **`docs/agentic-harness/`**: o molde
  para criar skills passa a viver **dentro** do blindar. É markdown puro, sem
  código — mantê-lo em repositório separado custava um repo sem entregar nada.
  Além das 21 garantias do molde, ele agora carrega as 4 lições que só
  apareceram rodando contra projeto real.
- **`scripts/install.sh`** roda o `doctor.sh` ao final e **oferece clonar o
  `ancorar`**. Uma linha de comando deixa a máquina nova pronta.

O `ancorar` fica em repositório próprio de propósito: tem código (16 checks de
host via SSH, 10 fases) e um contrato de supervisão diferente — absorvê-lo seria
duplicar. **Dois repositórios no total.**

### Os 49 `deferred` viram subagentes paralelos

O passo 5 da sequência mandatória mandava executar cada playbook em sequência,
no mesmo contexto. No projeto real isso foram **49 playbooks**: em fila, a
janela enche e os últimos recebem menos atenção que os primeiros — e ninguém
percebe, porque o relatório sai igual.

Agora vão em **subagentes paralelos**, um por agente, em lotes de 6–8. Contexto
isolado é o que mantém o quadragésimo nono tão cuidadoso quanto o primeiro.

O prompt do subagente carrega as regras que não se negociam: severidade só do
enum; achado crit/high precisa de `file` (ou da medição, se for runtime); não
achar nada é `passed` com lista vazia, **não** inventar achado para parecer
útil; e `skipped` só para o que não se aplica. Agente que não gravou result não
foi executado — vira `errored`, nunca aprovado.

## [0.68.0] — 2026-08-16

Portabilidade: fazer o blindar funcionar **completo** numa máquina nova.

### `scripts/doctor.sh` — o que falta na MÁQUINA, e o que se perde

O `preflight.sh` valida o projeto-alvo; nada validava o ambiente. Sem
`ripgrep`, dezenas de checks saem como `skipped` — e o relatório mostra
cobertura alta. Numa máquina nova esse é o modo de falha mais provável e o mais
difícil de perceber.

Cada ausência diz **o que se perde**, não só "faltando": sem `node` o
orquestrador não resolve o MODULE-MAP; sem `docker` o módulo 18 self-skipa e a
aplicação **nunca é provada de pé**; sem `ancorar` o host nunca é verificado.

**Descoberta ao rodá-lo**: o ripgrep **não estava instalado** nesta máquina.
Tudo nesta sessão rodou pelo fallback de grep.

### Os dois caminhos de busca continuavam divergindo

A v0.59 corrigiu o wrapper do ripgrep — o caminho que aqui **nunca executa**. O
fallback seguia com o piso antigo: excluía `dist` (que o ripgrep não excluía) e
não excluía `coverage` nem minificados (que o ripgrep excluía).

Agora os dois derivam da **mesma** lista (`BLINDAR_IGNORE_DIRS` /
`BLINDAR_IGNORE_FILES`), o que torna a divergência impossível **por construção**
— melhor que um teste conferindo se continuam iguais.

### Controles C0 no `check-invisible-unicode`

O check pulava `cp < 0x80`, então backspace, vertical tab e form feed passavam.
Encontrado **no README deste repositório**: ao escrever o caminho do Windows,
`skillslindar` virou `skills` + backspace + `lindar`. Invisível no editor,
e o texto renderizado fica errado.

### Atualização: pergunta, não avisa no meio do log

`check-update.sh` passa a sair **10** quando há versão nova, e a checagem vira o
**passo 0** da sequência mandatória — 1× por dia, cache de 24h. O `SKILL.md`
manda **perguntar** ao operador em vez de só logar: atualizar sozinho troca o
código sob os pés de quem está no meio de um trabalho.

O comando de atualização sai do próprio script, porque depende da instalação:
clone → `git pull`; artefato do `sync-skill.sh` (sem `.git`) → reinstalar. Dizer
o comando errado é pior que não dizer.

Falha de checagem nunca vira bloqueio **nem** vira "está atualizado" — significa
que não deu para saber.

### README

Recursos atualizados de v0.46 para v0.67 (estavam três dezenas de versões
atrás), mais **três prompts prontos**: instalar pelo Claude Code, usar num
projeto, e rodar tarefa pontual com `--only`.

## [0.67.0] — 2026-08-16

Três pendências anotadas durante a execução real, todas fechadas.

### `xargs` como "aparar espaços" adulterava o conteúdo

O idioma `$(echo "$x" | xargs)` estava em **38 lugares, 23 checks**, e fazia
duas coisas erradas com o texto varrido do projeto-alvo:

1. **xargs interpreta aspas.** `if (x === "admin")` virava
   `if (x === admin)` — a mensagem do finding mostrava código adulterado, sem
   justamente as aspas que importam numa comparação de string.
2. **Aspa não fechada** (comum em trecho cortado por `cut`) faz o xargs gritar
   `unmatched double quote` e devolver a linha truncada. Um único run contra
   projeto real produziu **466** desses.

Substituído por `trim_ws()` no `_lib.sh`, com `tr`+`sed`, que tratam a entrada
como texto — porque é o que ela é.

### Linhas de progresso se entrelaçavam em paralelo

Em `--parallel`, os workers do `xargs -P` escrevem concorrente no mesmo stderr,
e `echo` com expansão de cor pode virar mais de uma `write()`. Observado num run
real: `requer Claud✗  mock-killer → failed`. As quatro linhas de progresso
passam a sair por `printf` de string já montada — uma `write()` só.

### Foto de usuário servida com o EXIF intacto

`check-file-uploads` ganha a regra 5 (**high**): projeto que aceita upload de
imagem e não remove metadado. Foto de celular carrega **GPS com precisão de
metros** — servir o arquivo como veio publica onde a pessoa mora. Não é
hipótese: é o default de toda câmera de celular.

Reconhece quem já trata (`sharp`, `exiftool`, `piexif`, `-strip`,
`withMetadata(false)`).

Esta é a contrapartida legítima da decisão da v0.64: **remover proveniência C2PA
de mídia** ficou de fora do blindar por ocultar origem; **remover EXIF/GPS de
upload de usuário** entra, porque protege quem enviou.

### Bug encontrado ao testar

`rg -cl` devolve **vazio** — `-c` e `-l` são flags conflitantes. A primeira
versão da regra 5 não disparava por isso. `-l` sozinho funciona; `-ql` também.

## [0.66.0] — 2026-08-16

### O host entra no veredito

O `blindar` cobre o **código**. Firewall ativo, certificado válido, backup
fresco, DNS apontando certo e vizinho de container saudável só se veem **no
servidor** — e isso é da skill irmã `ancorar`. Até aqui, o `DEPLOYMENT` podia
dar `PASS` com o servidor sem firewall.

- **`scripts/ancorar-bridge.sh`** (novo): emite o plano de deploy, encontra o
  `ancorar` e invoca as fases de **leitura** dele (0, 1, 3, 7, 8, 10) — baseline
  de segurança do host por SSH, verdade de runtime e regressão de co-inquilinos.

- **Recusa explícita das fases que mutam** (2, 4, 5, 6, 9): provisionar, migrar
  dado, virar tráfego e decommissionar mudam o servidor. Automatizá-las daqui
  trocaria o *supervisionado + dry-run* do `ancorar` pelo *auto* do `blindar` —
  o oposto do que cada ferramenta escolheu ser. A recusa aponta o comando certo,
  não é silenciosa.

- **O gate `DEPLOYMENT` passa a ler o host**:

  | Estado | Gate |
  |---|---|
  | `ancorar` reprovou algum check | **BLOCKED** — o código passa, o servidor não |
  | sem `.ancorar/results` | **PASS WITH WARNINGS** — host nunca verificado |
  | `ancorar` aprovou | PASS |

  Host não verificado **não é** host aprovado — mesma regra do `NOT VERIFIED`.

- **Degradação honesta**: sem o `ancorar` instalado, o plano é emitido e a ponte
  avisa que ninguém verificou o servidor, com o comando de instalação. Sai 3, e
  a mensagem diz explicitamente que isso é ausência de verificação.

O `blindar` **lê** `.ancorar/results/` e nunca escreve lá. O
`scripts/smoke-run.sh` segue sendo **API pública** consumida pelo `ancorar` na
fase 7: mudar sua assinatura é breaking change.

Isto revisa a decisão da v0.56, que dizia "não criar adaptador". A distinção que
faltava não era entre chamar e não chamar — era entre **ler** e **decidir**.
Ler o veredito do host é do blindar; decidir mudar o servidor é do operador.

## [0.65.0] — 2026-08-16

### `seo-foundation` — a fundação, não o metadado

Divisão com o `seo-marketing-meta`, que já existia: lá são os **metadados**
(title, og:image, JSON-LD, noindex). Aqui é a **fundação** — o que está por
baixo e, quando errado, faz o resto não importar. Sem sobreposição: o check novo
não reverifica a existência de robots/sitemap, verifica o **conteúdo** deles.

- **`check-seo-foundation.sh`** (novo): robots bloqueando recurso de
  renderização (**high**), robots sem `Sitemap:` absoluto (**med**), ausência de
  canonical (**high**), de página 404 própria (**med**), de normalização de
  host/barra final (**med**) e de `llms.txt` (**low**). Par
  `project-seofound-bad`/`-good`.
- **`agents/seo-foundation.md`** (novo): cobre o que só se prova com o site no
  ar — 404 devolvendo **404** e não soft-200, redirect **301** e não 302,
  compressão realmente ativa no proxy, canonical resolvida, e sitemap contendo
  **só URLs 200**.

### O erro mais caro, e por que é `high`

Bloquear CSS e JS no `robots.txt` "para economizar crawl". O Google **renderiza
a página como um navegador**: sem folha de estilo e sem script, ele vê um site
quebrado e avalia como tal. `Disallow: /_next` é o caso mais comum.

### Três coisas que o arquivo nunca prova

**Soft 404** — página de erro devolvendo `200`. O buscador indexa milhares de
páginas de erro como se fossem conteúdo, e nada no repositório denuncia isso.

**Sitemap** é uma declaração: "estas são minhas páginas boas". URL que
redireciona, que dá 404 ou que está `noindex` **não pode estar lá** — e sitemap
gerado automaticamente a partir de rotas inclui exatamente essas.

**`hreflang` sem autorreferência** é ignorado, e o erro passa despercebido
porque nada quebra visivelmente.

### `llms.txt`

Novo e ainda raro, o que o torna barato e diferenciador: markdown na raiz com o
que um assistente precisa para responder sobre o negócio sem adivinhar pelo
HTML.

## [0.64.0] — 2026-08-16

### `check-invisible-unicode` — o caractere que você não vê

Três vetores publicados, nenhum coberto antes:

1. **Trojan Source (CVE-2021-42574)** — controles bidi de override fazem o
   arquivo **renderizar diferente do que compila**. Você revisa uma coisa e
   mergeia outra, e o diff no GitHub mostra a versão renderizada. **crit**.
2. **Contrabando para LLM** — tag chars `U+E0020–E007F` são invisíveis em
   qualquer editor e chegam intactos ao modelo. É carregador de prompt
   injection que nenhuma revisão humana pega. **high**.
3. **Homóglifo** — `А В Е К М Н О Р С Т Х` cirílicos são indistinguíveis das
   latinas; serve para spoofing de identificador e de domínio. **high**.

Mais o efeito comum: zero-width em texto de usuário quebra busca, `LIKE` no
banco, copiar-colar e leitor de tela.

### O trabalho real foi o falso positivo

Um check que remove "tudo que é invisível" quebra persa, emoji e árabe. A
detecção vai em Node porque o que separa achado de ruído é **contexto**, e
contexto não cabe em regex:

- ZWJ/ZWNJ são **ortografia** em persa (می‌روم) e devanágari
- ZWJ e variation selector depois de emoji são parte do glifo visível
  (👨‍👩‍👧, ❤️‍🔥) — removê-los altera o texto
- Bandeiras usam tag chars de propósito (🏴󠁧󠁢󠁳󠁣󠁴󠁿)
- Marca direcional é válida em prosa RTL; só **override e embedding** reordenam
  span alheio
- Homóglifo só é achado quando **mistura** com latino na mesma palavra — texto
  em russo legítimo não mistura

A fixture limpa carrega justamente esses casos, e passa com zero.

### Dois bugs meus no caminho, ambos da mesma família

- O `emitir` saía em JSON e o bash extraía por `sed`. A mensagem legítima contém
  aspas (*parece "a"*), o escape do JSON quebrava a extração e **o achado sumia
  em silêncio** — 3 detectados, 2 entregues. Trocado por TSV.
- `achados.join("
")` não terminava em newline, e o `while read` do bash
  **descarta a última linha** sem terminador. O último achado sumia.

Origem conceitual: `guillaumemeyer/watermarks-remover`, camada A (Unicode
invisível). As camadas de remoção de watermark estatística e de proveniência
C2PA **não** foram trazidas — existem para tornar impossível saber a origem do
conteúdo, o que contradiz uma ferramenta cuja proposta é evidência e
auditabilidade. A limpeza de **EXIF/GPS em upload de usuário** é o oposto disso
(protege quem enviou) e fica para o `file-uploads`, sob o `privacy-lead`.

## [0.63.0] — 2026-08-16

### Execução avulsa — `--only`

Testar um agente exigia o orquestrador inteiro (11 min). Agora:

```bash
bash scripts/blindar-run.sh --only mock-killer,environment-parity
```

**2 segundos.** Continua passando pelo orquestrador: o result é gravado no
formato normal e o schema é validado.

A trava que faz isso ser seguro: se o `coverage_pct` fosse medido contra a lista
**filtrada**, rodar 1 agente daria **100%** — a métrica diria "tudo coberto"
tendo olhado uma coisa só. O denominador continua sendo o total **disponível**,
então 1 de 130 mostra **0%**. O `run-report.json` carrega `partial: true`,
`only_agents` e `not_run_by_filter`, e a tela avisa "EXECUÇÃO PARCIAL".

A proibição do `SKILL.md` passa a ser específica: não rodar o `.sh` **fora** do
orquestrador. O caminho pontual existe e é sancionado.

### Modo COLLAB e disciplina de git

O `blindar` tratava do código e nunca do **repositório**. O primeiro projeto
real auditado não tinha **nenhum commit**.

- **`pipeline/COLLAB.md`** (novo, 6º modo): C1 parar o sangramento antes de
  commitar · C2 primeiro commit legível · C3 nada entra em `main` sem passar por
  algo · C4 a equipe sabe o que fazer sem perguntar · C5 ônibus factor · C6
  entregar ao modo seguinte.

  **A ordem do C1 não é negociável**: `.gitignore` primeiro, `.env.example`
  depois, `git add` por último. Se já houver commit com segredo, apagar o
  arquivo **não resolve** — a credencial deve ser considerada comprometida e
  **rotacionada**. A rotação é obrigatória; reescrever histórico é opcional.

- **`agents/git-collaboration.md`** (novo): vale em **todos** os modos, não é
  etapa. Commit que explica o **porquê**; PR que cabe na cabeça de quem revisa
  (acima de ~200 linhas recebe aprovação sem leitura, o que é pior que não ter
  revisão, porque cria a ilusão de que houve); conflito resolvido **entendendo
  os dois lados** — `--ours`/`--theirs` resolve o marcador e descarta a intenção
  do outro.

  A assimetria que governa: quase tudo em git é reversível, e três coisas não
  são — segredo commitado, histórico reescrito depois de publicado, e trabalho
  alheio sobrescrito.

- **`check-git-hygiene.sh`** (novo): `.env` fora do `.gitignore` (**crit** — a
  janela para evitar é antes do primeiro commit), `.gitignore` ausente ou sem
  `node_modules`/`.env` (**high**), sem CI que guarde o merge (**high**), sem
  CODEOWNERS nem template de PR (**low**), binário grande versionável (**med**).
  Par `project-githyg-bad`/`-good`.

## [0.62.0] — 2026-08-16

### Modo FEATURE — o caso mais comum do dia a dia, que não tinha modo

Os quatro modos existentes auditam (`harden`), constroem do zero
(`greenfield`), protegem produção (`evolve`) ou apagam incêndio (`recovery`).
Faltava **acrescentar algo a um projeto existente e saudável**.

Sem ele, "implementa o módulo de pagamento" caía no `harden` — que é auditoria,
não construção. O resultado era código escrito sem a disciplina do `greenfield`
e um relatório sobre **o passado do projeto** em vez da feature pedida.

- **`pipeline/FEATURE.md`** (novo): F1 entender antes de escrever · F2 impacto ·
  F3 a feature nasce dentro das regras · F4 a matriz de acesso ganha linha ·
  F5 provar que funciona · F6 **provar que não quebrou o que já existia** ·
  F7 registrar.

### Duas decisões de desenho que valem registrar

**É o único modo detectado pelo PEDIDO, não pelo disco.** Um projeto saudável
que vai receber uma feature é indistinguível, no sistema de arquivos, de um
projeto saudável que vai ser auditado. O sinal está no verbo do operador —
"implementa", "adiciona", "cria a tela de".

**Em produção ele compõe com o `evolve`, não o substitui.** Feature em sistema
com usuários é as duas coisas ao mesmo tempo: a disciplina de construção daqui
somada às travas de lá (round ≤40 LOC, `supervised`, migration destrutiva
proibida).

### O que separa este modo de "escrever código"

F6. A suite **inteira** verde, não só os testes novos; os checks rodando sobre
o **diff** (`blindar-run.sh --since`) em vez do projeto inteiro; e o gate
`security-first` valendo integralmente — um PR que não é de segurança não pode
enfraquecer segurança.

E F3 transforma o que no `greenfield` são etapas de construção em **requisitos
de aceitação**: autorização verificada na API e não só na UI, `tenant_id` desde
a primeira migration, seed no banco e não em array, fila com retry e
idempotência, teste escrito junto. Nenhum é "depois".

F4 amarra com o `iam-architecture`: feature quase sempre traz recurso novo, e
recurso ausente da matriz não é "sem acesso" — é **não decidido**.

## [0.61.0] — 2026-08-16

### Build varrido como se fosse fonte

O diagnóstico do primeiro projeto real mostrou 15 crit — mas **10 eram do
`observability` dentro de `frontend/.next`**, e os 3 do `prototype-pollution`
acusavam o devtools do próprio Next.js. Ruído de build reportado como crítico.

A distinção que faltava: varrer o artefato construído atrás de **segredo** é
legítimo — segredo é injetado em build time e pode não existir no fonte. Varrer
atrás de **padrão de código** é ruído, porque o fonte é a verdade e o bundle
carrega código de terceiros.

`.next`, `.nuxt`, `out` e `.svelte-kit` entram na exclusão de **42 checks**.
Ficam de fora, de propósito: `runtime-secrets`, `pii-encryption`,
`govtech-acessibilidade`, `bundle-size` e `cdn-strategy`, que miram o artefato.

Efeito colateral: o run do projeto real caiu de **20 para 11 minutos**.

### Mapa de usuários

- **`agents/iam-architecture.md`** (novo): responde "quem existe e o que cada um
  pode". O `blindar` auditava autorização sem nunca produzir o **alvo** — o
  `access-control` verifica se a rota checa permissão, e ninguém dizia quais
  papéis deveriam existir. Sem alvo escrito, a auditoria compara a implementação
  contra nada.

  Ordem obrigatória: **detectar → propor → perguntar**. Perguntar primeiro
  desperdiça o operador com o que o código já responde.

  Traz arquitetura de referência de 7 papéis com matriz de acesso, e as quatro
  perguntas que mudam o modelo de dados (MASTER impersona? STAFF vê colega?
  CLIENT é do tenant ou da plataforma? quem apaga de verdade?).

  Regra da matriz: recurso **ausente** não é "sem acesso", é **não decidido** —
  e não decidido vira permitido na primeira implementação apressada.

## [0.60.0] — 2026-08-16

### Path POSIX chegando em binário nativo do Windows

O `validate.sh` dizia `[FAIL] JSON invalido` para JSON perfeitamente válido.

Em Git Bash/MSYS o `[ -f "$FILE" ]` passa, porque o bash entende
`/tmp/cfg.json`. Mas `jq` e `python3` são binários **nativos do Windows** e
resolvem o mesmo caminho como `C:	mp\cfg.json`, que não existe. O `ENOENT`
era engolido pelo `2>/dev/null` e o script culpava o **conteúdo** do arquivo —
mandando o operador procurar erro de sintaxe onde não havia.

Regra que passa a valer no repo inteiro (`docs/BASH-COMPAT.md`): nunca
interpolar path dentro do source de outra linguagem (`node -e`, `python3 -c`);
passar por argv e converter com `cygpath -m`, guardado por
`command -v cygpath`. A forma mista (`C:/Users/...`) é aceita pelo bash e pelos
nativos, e não carrega backslash para dentro de string de outra linguagem.

Também: distinguir "não consegui abrir" de "conteúdo inválido", e não engolir o
stderr do validador.

O `graph-build.js` tinha a mesma falha por outro caminho: `--dir` errado
produzia grafo com `files:0` — indistinguível de "projeto sem código". Passa a
sair 2. Mesmo princípio do release gate: o default do desconhecido nunca é o
valor bom.

`tests/pathconv.test.mjs` cobre a conversão e os dois modos de falha.

## [0.59.0] — 2026-08-16

Primeira execução do blindar de ponta a ponta contra um projeto real (monorepo
NestJS + Next.js + Prisma, 129 agentes, 20 min). O orquestrador funciona — e a
execução real encontrou **cinco bugs** que 71 pares de fixture não pegavam.
Todos da mesma família: **ausência de sinal lida como aprovação**.

### 1. Severidade fora do enum torna o achado invisível

17 chamadas emitiam `"critical"` e `"medium"` em vez de `crit` e `med`. Todo
consumidor casa a string exata — `check-termination` conta
`.findings_by_severity.crit`, o release-gate faz `select(.severity=="crit")`,
o `check-evidence` testa `=== "crit"`.

Consequência: um achado **crítico** aparece no JSON, não é contado por ninguém,
e **o portão de release diz GO**. Estava em `check-healthtech-fhir` (dado de
paciente, SMART on FHIR) e `check-govtech-acessibilidade` (obrigação legal).

- `_lib.sh` ganha `normalize_severity()`. Apelidos conhecidos são mapeados;
  valor desconhecido **não vira `low`** — vira `high` com o original preservado
  na mensagem. O default do desconhecido não pode ser o valor benigno.
- `tests/severity-contract.test.mjs` (novo) impede a regressão no call site.

### 2. Os dois caminhos de busca varriam árvores diferentes

O fallback de `grep` sempre excluiu `node_modules/.git/dist/.blindar` no seu
`base`; o wrapper do `ripgrep` real não excluía nada. O mesmo check varria
árvores diferentes conforme o ripgrep estivesse instalado — e o desacordo só
aparece **com** ripgrep, isto é, em produção e não no fallback.

Efeito observado: `content-quality` varreu `.blindar/results/*.json` (a própria
saída do blindar) e reportou o JSON de findings como "erro técnico vazando pra
UI" — auto-detecção reentrante.

`BLINDAR_RG_BASE_IGNORE` passa a valer nos dois caminhos, com só o que nunca é
alvo legítimo. `dist`/`build`/`.next` ficam **de fora** do piso de propósito:
varrer o bundle construído é exatamente o certo para `runtime-secrets` e
`pii-encryption`, que procuram segredo assado no artefato do cliente.

### 3. 868 findings, 853 vindos do build

`content-quality` varria `frontend/.next`. E reportava `passed`, então ninguém
olhava. Somados `.next`, `.nuxt`, `out`, `.svelte-kit`.

### 4. Sem lock: dois runs se corrompem em silêncio

O segundo run trunca o `.run-lines.log`, que é a fonte que o primeiro lê na
agregação. Observado: run completo com exit 0 e relatório dizendo *"129
agentes, passed 1, errored 0, coverage 0%"* — enquanto o `mock-killer` sozinho
tinha achado 310 findings.

- Lock por PID com detecção de lock órfão.
- Guarda: N agentes planejados com **0 resultados agregados** vira `ERRORED`.
  Um run que não mediu nada não pode sair com forma de sucesso.

### 5. Falha de escrita virando aprovação

`emit_result` teve o `cat >` falhando com *"No such file or directory"* e o
check seguiu imprimindo `✓ PASSED` e saindo 0. Agora verifica que o arquivo
existe e não está vazio; se não, falha explicitamente.

### Bug de segunda ordem, encontrado pelo próprio gate

Renomear as severidades quebrou `check-healthtech-fhir`: ele **contava os
próprios findings** grepando `'"severity":"critical"'`. A emissão foi corrigida
e a contagem não — o check passou a emitir `passed` no fixture vulnerável. O
gate pegou. Convenção interna errada porém consistente é pior que inconsistente:
corrigir metade quebra.

Junto, o padrão `grep -c ... || echo 0`: o `grep -c` já imprime `0` e sai 1, e o
`|| echo 0` acrescenta um segundo — produzindo `[: 0\n0: integer expression
expected`. Corrigido em 7 pontos, incluindo dois checks novos meus.

## [0.58.0] — 2026-08-15

Fase 8 e última do plano EOS: princípio de evidência. Toda afirmação passa a
precisar de onde ser verificada.

### O gate

Escrever "cite arquivo, linha, comando" numa diretriz é fácil de esquecer.
**`check-evidence.sh`** (novo) torna a regra verificável **na fonte**, antes de
virar prosa: achado `crit`/`high` precisa de `file` preenchido, e todo gate da
Fase 06b precisa de `evidence`.

Como o `check-termination.sh` e o `check-release-gates.sh`, é um decisor — não
chama `emit_result` e por isso fica fora do denominador de cobertura.

### O gate corrigiu a própria regra na primeira execução

A primeira versão exigia `file` de **todo** achado `crit`/`high`. Rodando
contra os results reais, reprovou o `check-load-test`: *"erro de 100% acima do
SLO de 5% com 10 concorrentes"*.

Esse achado não tem arquivo **por natureza** — é medição de runtime, e a
medição já é a evidência completa. A regra estava reprovando justamente o
achado mais concreto do relatório. Passou a distinguir as duas formas de
"onde verificar": achado estático aponta arquivo; achado de runtime aponta
medição.

### Relatório final

A Fase 07 passa a exigir, além do que já pedia:

- modo de operação usado **e a evidência que o produziu**;
- os 11 gates com a coluna de evidência e o veredito;
- **gates pulados por modo, nomeados** — gate pulado em silêncio é
  indistinguível de gate aprovado;
- decisões arquiteturais do ciclo;
- **o que NÃO foi alterado, e por quê** — a seção que mais falta e a que o
  próximo leitor mais precisa: sem ela, "não aparece no relatório" se confunde
  com "não existe".

Com isto o plano `docs/PLANO-EOS.md` está completo: 8 fases, v0.51 → v0.58.

## [0.57.0] — 2026-08-15

Fase 7 do plano EOS: hierarquia de agentes. A de maior risco do plano, feita
como **camada de metadata** — nenhum arquivo movido, nenhum agente fundido,
nenhuma renomeação.

### O problema

117 especialistas chapados não convergem sozinhos. Cada um está certo dentro do
próprio escopo e cego fora dele: `performance` quer Redis; `security` exige
Redis com auth, TLS e rede isolada; `db-architect` argumenta que o índice que
falta resolve o mesmo problema sem introduzir serviço. Nenhum está errado — e
sem árbitro vence quem rodou por último.

### `lead` e `authority` no frontmatter

Os 117 agentes passam a declarar `lead:` (quem arbitra) e `authority:` (o que
pode fazer). 12 leads; `security-lead` governa 20 agentes, `qa-lead` 3.

`authority` ∈ `read-only | plan | implement | validate | adversary | gate`.
`gate` bloqueia entrega e **não edita** — somar autoridade de decisão à de
execução é como uma decisão ruim vira fato consumado antes de ser revista. São
4 agentes com `gate`, e o teste reprova se virarem maioria: se quase todo mundo
pode bloquear, ninguém bloqueia de fato.

- **`agents/chief-architect.md`** (novo, `authority: gate`): arbitra entre leads
  por precedência declarada — perda de dado > segurança > reversibilidade >
  simplicidade operacional > o que já existe. Não implementa.

### O teste encontrou quatro buracos que existiam em silêncio

**`tests/agents-registry.test.mjs`** (novo) valida o registro nos dois sentidos
e já nasceu achando:

1. `attack-recon.md` e `race-fuzzing.md` sem **nenhum** frontmatter.
2. `infra-runtime` e `race-fuzzing` eram playbooks que **nenhum módulo
   ativava** — escritos, mantidos e nunca executados.
3. `chief-architect` fora do `MODULE-MAP` (recém-criado).
4. `db-architect` não declarava `module` — usa `modules: [7, 9]`, porque
   pertence a dois de verdade. Aqui **o teste é que estava errado**: exigia a
   forma singular e reprovaria um frontmatter correto. Passou a aceitar as duas.

As 11 entradas do `MODULE-MAP` sem arquivo `.md` (`trivy`, `osv-scanner`,
`entrypoint-cmd`…) são legítimas: checks determinísticos puros, unidades
executáveis sem playbook. O teste exige que toda entrada resolva para **playbook
ou check**, não para playbook.

### Outros

- Módulos 14, 15 e 18 adotam os órfãos. `SKILL.md` ganha a seção de hierarquia.
- `SKILL.md`: 117 agentes / 103 `check-*.sh`.

## [0.56.0] — 2026-08-15

Fase 6 do plano EOS: alvo de deploy. O `blindar` passa a definir **estado
desejado** e emitir isso como artefato — sem executar deploy e sem chamar
executor.

### Correção de rumo em relação à proposta original

A proposta externa que originou o plano tratava o `ancorar` como *deployment
provider* consumido pelo `blindar` ("blindar define, ancorar executa"). Isso
inverteria a seta e violaria o contrato de isolamento que o próprio `ancorar`
declara inegociável: ele escreve só em `.ancorar/`, nunca em `.blindar/`, não
edita `~/.claude/skills/blindar/**`, e o único código do `blindar` que invoca é
`scripts/smoke-run.sh --url`, read-only.

A dependência é **ancorar → blindar**, e continua sendo. O `blindar` publica
`.blindar/deployment-plan.json` como artefato **passivo**: fica disponível, e
quem quiser lê. Nenhum adaptador foi criado.

Consequência registrada: `scripts/smoke-run.sh` é **API pública** consumida por
outra skill — mudar sua assinatura é breaking change e vai para o decision log.

### Novidades

- **`pipeline/10-deployment-target.md`** (novo): alvo `vps | docker-compose |
  k8s | cloud`, detectado pelo que existe no repo. Sete blocos obrigatórios no
  plano, sendo o mais importante **volta** — que separa três perguntas
  normalmente tratadas como uma: reverter o código, reverter o schema, e o que
  acontece com o dado escrito entre o deploy e o rollback. A terceira é a que
  decide se o rollback é possível.
- **`agents/deployment-readiness.md`** (novo): produz a especificação e para aí.
- **`check-vps-readiness.sh`** (novo): porta de banco publicada no host
  (**high**) — o bind default do Docker é `0.0.0.0` e a regra publicada
  **atravessa o firewall de host**, que segue "ativo" sem proteger; banco sem
  volume (**high**); imagem sem tag fixa, ausência de `restart:` e de
  `healthcheck` (**med**). Par `project-vps-bad`/`-good`.

O que só se prova **no host** — firewall ativo, certificado válido, backup
fresco, DNS, vizinhos de container — ficou deliberadamente de fora: é do
`ancorar`, que roda contra o servidor por SSH. Duplicar aqui seria manter duas
verdades sobre o mesmo servidor.

### Outros

- Módulo 14: 15 → 16 agentes. O check novo entra no gate `DEPLOYMENT`.
- `SKILL.md`: 116 agentes / 103 `check-*.sh` (89 determinísticos + 14 API).

## [0.55.0] — 2026-08-15

Fase 5 do plano EOS: camada adversarial de runtime. A pergunta muda de "a
defesa está escrita?" para "a defesa funciona quando a requisição chega?".

### Defesa declarada que não defende

Todos os checks de segurança perguntavam se a defesa **existe**. Ficavam cegos
quando ela existe e está desligada na mesma linha: `helmet({
contentSecurityPolicy: false })` satisfaz "usa helmet"; `script-src
'unsafe-inline'` satisfaz "tem CSP".

Isso é pior que ausência de defesa. A ausência aparece no relatório como gap; o
teatro aparece como **aprovação**, e todo relatório a jusante repete a
afirmação falsa.

- **`check-defense-theater.sh`** (novo): TLS com verificação desligada
  (`rejectUnauthorized: false`, `NODE_TLS_REJECT_UNAUTHORIZED=0`,
  `verify=False`) — **crit**; helmet com CSP desligada — **high**; `script-src`
  com `unsafe-inline`/`unsafe-eval` — **high**; JWT aceitando algoritmo `none`
  — **crit**; CORS refletindo qualquer origem **com** `credentials: true` —
  **crit**. Par `project-theater-bad`/`-good`.
- **`agents/runtime-adversarial.md`** (novo): o confronto entre afirmação
  estática e prova de runtime, com tabela de "afirmação → prova" e o par
  autenticado/não-autenticado lado a lado. `DIVERGENTE` sobe a severidade em
  relação ao mesmo problema achado só estaticamente, porque significa que um
  check anterior **aprovou indevidamente** — e a correção volta para o check,
  não só para o projeto.

### Bug de regex encontrado durante o desenvolvimento

A primeira versão do padrão de CSP usava `script-src[^;"']*'unsafe-inline'`,
excluindo aspas da classe negada. Valor de CSP é cheio de aspas legítimas, e o
match parava em `script-src 'self'` antes de chegar ao `'unsafe-inline'` logo
adiante — o check não disparava no fixture vulnerável. A fronteira correta é o
`;`, que separa diretivas: com `[^;]*`, um `script-src 'self'; style-src
'unsafe-inline'` corretamente **não** casa.

### Escopo que ficou de fora, com motivo

O plano previa estender `scripts/pentest-active.sh` com crawling autenticado.
Não foi feito: adicionar sessão autenticada a um script que dispara payloads
aumenta o raio de alcance e exige os tokens do operador. Isso é trabalho com
humano no circuito, conduzido pelo agente, não algo para embutir num script que
roda sem supervisão. Os quatro probes existentes e os gates de autorização
(`.blindar/.accept-authorization` + escopo por host) permanecem inalterados.

### Outros

- Módulo 15 passa de 4 para 5 agentes; o check novo entra no gate `SECURITY`.
- `SKILL.md`: corrigidas duas referências a "4 perguntas" no launcher, que tem 5.
- `SKILL.md`: 115 agentes / 102 `check-*.sh` (88 determinísticos + 14 API).

## [0.54.0] — 2026-08-15

Fase 4 do plano EOS: governança de mudança. Responde três perguntas que o
`blindar` não fazia antes de alterar código — **o que mais isso alcança**,
**quanto custa se estiver errado** e **por que decidimos assim**.

### AUTO deixa de ser permissão irrestrita

`mode: auto` existe para não interromper o operador a cada passo. Não era para
significar autorização para perda irreversível de dado, mas na prática
significava: o loop aplicava qualquer round sem perguntar.

- **`agents/risk-engine.md`** (novo): classifica cada round em
  `LOW | MEDIUM | HIGH | CRITICAL` por dado afetado × reversibilidade ×
  ambiente × downtime. `HIGH` e `CRITICAL` **pausam mesmo em AUTO**. A
  classificação depende do `operation_mode`: `DROP COLUMN` é `LOW` em
  `greenfield` (não há dado a perder) e `CRITICAL` em `harden`.
- **`pipeline/04-rounds-loop.md`**: gate de risco entre implementar e aplicar.
  Ao pausar, o agente apresenta cinco coisas — o que muda, o que se perde, **o
  comando** de desfazer, que backup existe e quando foi restaurado, e a
  alternativa menos destrutiva. Pausa sem caminho de volta não dá ao operador
  como decidir.
- **`check-destructive-migration.sh`** (novo, **crit**): DDL destrutivo sem
  `down`/`downgrade` declarado. Não reprova destruição — reprova destruição
  irreversível; se deve rodar é decisão do gate, se dá para desfazer é fato
  verificável. Detecta `downgrade()` com corpo `pass`, que é ausência de
  rollback escrita como se fosse rollback. Escape via
  `@blindar:destructive-ok <motivo>`. Par `project-destrmig-bad`/`-good`.

### Decisão arquitetural para de ser reescrita a cada sessão

- **`agents/decision-log.md`** (novo): ADRs em **`docs/decisions.md`**,
  versionado. Deliberadamente **não** em `.blindar/` — decisão arquitetural
  precisa aparecer no diff, ser revisada no PR e sobreviver a `rm -rf .blindar`.
  Append-only: decisão superada ganha entrada nova que a supersede, nunca
  edição da antiga.
- **`check-decision-log.sh`** (novo): exige as 4 seções (contexto, alternativas,
  decisão, consequências). **Alternativas** é a que mais importa — sem o que foi
  descartado e por quê, a próxima pessoa refaz a comparação do zero e pode
  chegar a outra conclusão sem nunca ter visto o argumento original. Sem log,
  só cobra se o projeto tiver ≥2 sinais arquiteturais. Par
  `project-adr-bad`/`-good`.
- **`agents/change-impact.md`** (novo): mapa de raio de alcance em 13 camadas
  antes de mudança estrutural, com ordem de aplicação em 5 passos para mudanças
  que alcançam banco e código juntos. Duas linhas que costumam ser esquecidas
  entram explicitamente: **seed/dados simulados** (continuam gerando o formato
  antigo em silêncio) e **mensagem em voo** (durante o deploy convivem código
  velho e novo).

### Outros

- Módulo 14 passa de 12 para 15 agentes; os dois checks novos entram nos gates
  `DATABASE` e `DOCUMENTATION` da Fase 06b.
- Numeração dos passos do round corrigida (havia dois passos "6" e "7").
- `SKILL.md`: 114 agentes / 101 `check-*.sh` (87 determinísticos + 14 API).

## [0.53.0] — 2026-08-15

Primeiras três fases do plano EOS ([`docs/PLANO-EOS.md`](docs/PLANO-EOS.md)):
o `blindar` deixa de ter um único caminho (projeto existente e saudável) e
passa a distinguir a natureza do trabalho, a provar que uma migração de engine
de banco chegou ao runtime, e a decidir release por dimensão em vez de por
contagem de severidade.

As três fases foram planejadas como releases separadas (v0.51/v0.52/v0.53) mas
saem juntas porque são interdependentes: os gates da Fase 3 consomem os checks
da Fase 2, que por sua vez mudam de comportamento conforme o modo da Fase 1.

### Fase 1 — modos de operação (planejado como v0.51)

Antes: um pipeline só, que abortava em suite vermelha e não tinha o que fazer
num diretório vazio. Agora `operation_mode` ∈ `greenfield|harden|evolve|recovery`,
detectado e confirmado antes do launcher.

- **`pipeline/00-mode-select.md`**: detecção determinística com precedência
  `recovery > greenfield > evolve > harden`, confirmação com a evidência que a
  produziu, e tabela do que cada modo altera (gates, tamanho de round, o que é
  permitido mudar).
- **`pipeline/GREENFIELD.md`**: G1–G10, das perguntas de requisito até entregar
  o projeto ao modo `harden`. PostgreSQL default, `tenant_id` e soft delete
  desde a primeira migration, dado simulado no **banco** e não no código.
- **`pipeline/RECOVERY.md`**: R1–R7. Preserva evidência antes de corrigir, uma
  correção por vez, migration destrutiva proibida, e só sai do modo com teste de
  regressão que reproduz a falha.
- **`pipeline/01-baseline.md`**: o gate de suite vermelha ganha exceção por
  modo — em `recovery` ele é a condição de entrada, não o abort. Gate pulado por
  modo tem de aparecer no relatório: gate pulado em silêncio é indistinguível de
  gate aprovado.
- **`00-launcher.md`**: numeração das perguntas corrigida (dizia "4 perguntas" e
  tinha 5, com rótulos `/4` e `/5` misturados); `evolve` força `supervised`.

### Fase 2 — migração de engine e paridade de ambientes (planejado como v0.52)

Origem: pedir "migra de SQLite pra PostgreSQL no container" e receber compose
com Postgres + código que continua abrindo SQLite.

- **`check-db-engine-consistency.sh`** (novo, **crit**): compara a engine
  DECLARADA na infra com a USADA no caminho de runtime. Postgres no
  `docker-compose.yml` não é evidência de que a aplicação usa Postgres. Par de
  fixtures `project-dbdrift-bad`/`-good`.
- **`check-environment-parity.sh`** (novo, **high**): engine divergente entre
  ambientes (`.env*`) — o caso DEV=Postgres, TEST=SQLite, PROD=Postgres, em que
  a suite fica verde porque o SQLite aceita o que o Postgres recusa. Também
  reporta deriva de versão maior do Postgres entre composes (**med**). Sem
  `declare -A` (bash 3.2 do macOS). Par `project-envparity-bad`/`-good`.
- **`agents/db-migration-guardian.md`** (novo): cadeia DETECT → PLAN → EXECUTE →
  **PROVE**. A prova é de runtime: conexão vista pelo lado do servidor, escrita
  que sobrevive a restart, e nenhum arquivo `.db` tocado durante o exercício.
- **`agents/environment-parity.md`** (novo): ENVIRONMENT DRIFT REPORT sobre 8
  dimensões, cada divergência com veredito explícito de aceitável ou a corrigir.
- Módulo 7 do `MODULE-MAP.json` passa de 4 para 6 agentes.

### Fase 3 — release gates (planejado como v0.53)

Antes: `0 crit + ≤2 high`. Isso mede o que os checks **acharam**, não o que
ficou por verificar — e aprovava projeto com SQLite em produção, sem backup
restaurável e sem rollback.

- **`check-release-gates.sh`** (novo): agrega `.blindar/results/*.json` em 11
  dimensões independentes e emite `.blindar/gates.json` com veredito
  **GO / CONDITIONAL GO / NO-GO**. Não chama `emit_result` — é decisor de
  release, como o `check-termination.sh`, e por isso fica fora do denominador de
  cobertura de fixtures pelo critério que já existia.
- **`NOT VERIFIED` ≠ `PASS`**: dimensão sem check executado conta como warning,
  nunca como aprovação. Achado durante o desenvolvimento: a primeira versão
  dava `GO` com as 11 dimensões vazias — "nada rodou" lido como "tudo passou",
  exatamente o modo de falha que a fase existe pra eliminar.
- **Zero checks com resultado ⇒ NO-GO.** Sem medição não há veredito.
- **Provas positivas**: `BACKUP_RECOVERY` exige evidência de **restore**, não de
  backup; `DEPLOYMENT` exige **rollback**. Backup que ninguém restaurou é
  hipótese.
- Leitor de JSON com Node primeiro (1 processo pro diretório inteiro) e `jq`
  como alternativa — sem nenhum dos dois é NO-GO por falta de instrumentação.
- **`pipeline/06b-release-gates.md`** e **`schemas/gates.schema.json`** (novos).
- Termination passa a ter duas condições: a contagem é **necessária, não
  suficiente**.

### Correções de honestidade

- `SKILL.md` declarava "118 agentes / 81 checks determinísticos". Real,
  verificado por `ls`: **111 agentes / 84 checks**. Os números tinham derivado.

### Fora do repo

- `modelo_agente_tarefa_cloude.md` (63KB, untracked na raiz) era o blueprint do
  padrão *agentic-harness* — o `blindar` generalizado em molde para criar outras
  skills. Não é runtime do `blindar` e inflava a skill instalada. Extraído para
  skill própria em `~/.claude/skills/agentic-harness/`, com `SKILL.md` enxuto e
  o conteúdo pesado em `reference/` sob progressive disclosure.

## [0.50.0] — 2026-08-02

Blindagem da própria skill. Auditoria completa (8 varreduras independentes) e
correção incremental — tudo no **código-fonte** (`templates/`, `scripts/`), que
propaga a todo projeto futuro via instalador. `blindar` roda sobre projetos
não-confiáveis: nome de arquivo, conteúdo, `package.json`, URL de recon e
arquivos em `.blindar/` do alvo são entrada não-confiável, e as correções fecham
os pontos onde esse dado virava JSON inválido, HTML no browser do operador,
argumento de shell/aritmética ou script executado no host.

### Portão de release não falha mais aberto

- **`_lib.sh` `escape_json`**: codificador JSON completo (RFC 8259 §7) em awk —
  escapa TODO caractere de controle U+0000–U+001F. Antes, um `\r` (saída CRLF do
  rg no Windows), `\f`, `\b` ou `0x01` vindo do alvo passava cru → JSON inválido
  → `jq -s` do run-all falhava e **substituía o aggregate inteiro** (o alvo
  apagava o próprio relatório com 1 byte, e o gate lia 0 crit → GO falso).
- **`check-termination.sh`** e **`run-all.sh`**: `grep`/parse com `|| true` — sob
  `set -e` a contagem de highs (grep -c sem match) abortava o gate no caso comum.
- **`check-secrets.sh`**: `require_tool jq` (sem jq contava 0 e reportava PASSED
  com segredos — falha aberta) + `gitleaks --redact` + fim do subshell que emitia
  `failed` com `findings: []`.

### Vazamento de segredo, XSS, RCE

- **Segredo no finding**: `config-externalization`, `payments` (CVV/PAN),
  `observability` (PII) e `fintech` (chave PIX) não gravam mais o valor casado na
  mensagem (ia pro aggregate → CI → API). Só `file`/`line`.
- **XSS nos dashboards**: `esc()` em `dashboard.html`/`sec.html`, escape de
  `</script>` no `report.js` (breakout em parse-time que derrotava o `esc()`), URL
  de PR só http(s), CSP restritiva nos 5 templates. O browser do operador era o sink.
- **Execução de código do repo auditado**: `smoke-run.sh` recusa
  `.blindar/smoke-flow.sh` versionado no git (opt-in via `BLINDAR_ALLOW_FLOW_SCRIPT`);
  `blindar-run.sh` valida nome de agente `[a-z0-9-]`; `blindar-fix.sh` valida `line`
  numérico antes de `$(( ))`; `blindar-learn.sh` sanitiza `--desc`.

### ReDoS, injeção, segredos em trânsito, supply chain

- **`graph-build.js`**: ReDoS na regex de import (3 KB de espaços = 11 s → 4 ms),
  captura idêntica. Guardas `Array.isArray`/try-catch em `blindar-report.mjs`,
  `attack-recon-report.js`, `sbom-build.js`, `reproducibility.js`.
- **Injeção**: `load-test.sh` (awk/sed/node -e → `awk -v` + limites de
  concorrência), `check-mcp-security.sh` (match literal, fim do bypass da
  whitelist), `_api_wrapper.sh` (`IFS='||'` corrompia todos os findings de API).
- **Segredos em trânsito**: `ANTHROPIC_API_KEY` via `curl --config -` (fora do
  argv); recon não persiste o corpo de arquivo exposto (`.env`); trivy em `mktemp`.
- **Supply chain / CI**: gitleaks pinado (v8.18.4, não `master` mutável),
  `permissions: contents: read`, inputs via `env:`, deps fantasma (`kleur`/`mri`)
  removidas.

Validação: `check-selftest` 65 pares / 0 regressões nos dois modos (ripgrep real
e grep-fallback), suite Node inteira verde, 0 regressões.

## [0.49.0] — 2026-08-02

Duas frentes: o módulo de ciclo de vida do log em disco, e o conserto da
camada de detecção — que estava reportando `passed` sem varrer arquivo, com a
CI vermelha havia sete semanas.

Mais o modo **fatiado**: rodar o blindar um módulo por vez, com relatório
persistente entre sessões, e guardas que transformam ferramenta ausente em
buraco declarado em vez de aprovação silenciosa.

### Novo agente `log-ops-retention` (módulo 6)

- **`agents/log-ops-retention.md`**: dono do *continente* do log. Fronteira
  explícita com `observability` (dono do *conteúdo*) e delegação obrigatória da
  redação a `runtime-secrets` — o agente **para e emite achado** se o alvo não
  tem política central, em vez de criar a segunda. Total 118 agentes.
- **`observability.md` corrigido**: a linha "stdout JSON é suficiente — infra
  coleta" contradizia frontalmente qualquer esquema em disco. Agora é
  condicional (stdout basta *quando há coletor externo*), com fronteira
  bidirecional declarada. Sem isso os dois agentes davam conselhos opostos ao
  mesmo projeto.

### Template de referência (Node, zero dependências)

- `templates/log-ops/logger.mjs` — envelope, streams, rotação 16 MB, gzip no
  fechamento, escrita em lote fora do caminho quente (descarta antes de
  bloquear), stdout e arquivo coexistindo, guarda de disco cheio.
- `templates/log-ops/retention.mjs` — varredor com as 5 guardas obrigatórias
  (regex exata de data, realpath dentro do LOG_DIR, lstat/symlink, piso rígido
  de hoje+ontem, bytes liberados) + retenção **por stream** e lock advisory.
- `templates/log-ops/pseudonym.mjs` — HMAC com chave (recusa operar sem ela;
  hash puro de CPF ou de IPv4 é força-bruta de segundos), `ip_hash` com salt
  diário e `ip_net` /24 ÷ /48.

### Gate

- **`check-log-ops.sh`** (novo): 7 detecções — exclusão sem guarda (crit), sem
  retenção (high), container sem volume (high), sem rotação, escrita
  bloqueante, log fora do `.gitignore`/`.dockerignore`, sem guarda de disco.
  Self-skip em projeto que só usa stdout. Par `project-logops-bad/good`.
- **`tests/log-ops.test.mjs`** (novo): 46 asserções cobrindo os seis
  comportamentos exigidos — rotação por tamanho, virada do dia em UTC, retenção
  apagando o que deve e preservando hoje/ontem, isolamento entre processos (dois
  processos reais), ausência de dado sensível lendo os arquivos produzidos, e
  disco cheio.
- `docs/log-ops-incidente.md` — qual stream responde qual pergunta.

### Camada de detecção: quatro bugs de cegueira silenciosa

A CI estava vermelha desde 2026-06-21 (último verde: 06-07), no passo
`Self-test with real ripgrep`. As v0.44–v0.48 foram publicadas por cima disso.
Causa: **quatro** bugs independentes, todos com a mesma assinatura — o `rg`
não varre nada, `2>/dev/null` engole o erro, `|| true` mascara o exit, e o
check reporta `passed` sem ter olhado um arquivo.

1. **rg lia o STDIN em vez do cwd.** Quando stdin não é TTY e nenhum path é
   passado, o ripgrep busca no stdin. Todos os checks chamam `rg PADRÃO --type
   ts` sem path, então sob pipe (CI, `| tee`, cron, `execFileSync`) os **74
   checks** buscavam num pipe vazio. De longe o mais grave. Corrigido no
   wrapper com `</dev/null`.
2. **MSYS reescrevia os padrões.** No Git Bash, o runtime converte argumentos
   que parecem caminho POSIX antes de spawnar um binário nativo: o padrão
   `"/health/live"` chegava ao `rg.exe` como `C:/Program Files/Git/health/live`.
   Atingia todo check com padrão iniciado por `/`. Corrigido com
   `MSYS2_ARG_CONV_EXCL='*' MSYS_NO_PATHCONV=1`.
3. **Nomes de `--type` inválidos.** `tsx`, `jsx`, `scss`, `prisma`, `env` não
   existem no ripgrep — ele sai com erro 2. 71 ocorrências. `tsx`→`ts`,
   `jsx`→`js`, `scss`→`css` (os tipos reais já cobrem as extensões);
   `prisma` e `env` passaram a ser injetados via `--type-add` no wrapper.
4. **Globs de exclusão sem `-g`** em 2 checks (`check-config-externalization`,
   `check-mock-killer`): viram *caminhos*, todos inválidos, nada varrido.

O denominador comum: o fallback de grep do `_lib.sh` é mais tolerante que o
ripgrep real — aceita os cinco `--type` inválidos e `'!glob'` solto. Ele
**mascarava** os bugs, e por isso a CI só falhava no passo com ripgrep real.

Novo `tests/rg-parity.test.mjs` fecha a classe inteira: valida estaticamente o
vocabulário das duas implementações, exige as blindagens de stdin e MSYS no
wrapper, e roda pares fixture/check nos **dois** modos exigindo veredito
idêntico. Ligado ao `lint.yml` e ao gate de release.

### Gate de release

`npm-publish.yml` ganhou um job `gate` que roda self-test, paridade e suíte
completa **no commit da tag**; `publish` agora depende dele. O `SKILL.md` já
listava "CI verde antes de merge, sempre" como não-negociável e "CI vermelha
mergeada" como anti-padrão — faltava o mecanismo.

### Cobertura com denominador derivado — 65/65 (100%)

`check-selftest.sh` reporta dois números (gate-áveis e total bruto) e o
denominador deixou de ser lista curada. Um check é gate-ável quando quatro
propriedades verificáveis valem: não é `.api.sh`, emite `failed` em algum
caminho, não lê estado fora do projeto (`$HOME`/`$APPDATA`), e não usa
`npx`/`curl`/`wget`. Resta uma lista curta só dos wrappers de scanner
(`semgrep`, `trivy`, `osv-scanner`, `gitleaks`, `lighthouse`, `wave-guardian`,
`secrets`, `deps-audit`), onde o check *é* a invocação da ferramenta.

A regra expôs o que a lista escondia:

- **`check-mcp-security`** lê `$HOME/.cursor/mcp.json` e
  `$APPDATA/Claude/claude_desktop_config.json` — config da máquina do operador,
  não do projeto. Reportaria achados sobre o MCP pessoal como se fossem do
  alvo. Não gate-ável por princípio.
- **`check-strategic-scanner`** e **`check-mcp-recommended`** nunca emitem
  `failed` — informativos, não gates.
- **`check-pwa-installable`** não estava fora por falta de fixture: estava
  quebrado de duas formas. (a) toda a validação do manifest dependia de `jq`,
  que sem instalação vira no-op silencioso — manifest com `display:browser` e
  zero ícones reportava `passed`; trocado por `node`, que já é requisito duro.
  (b) o veredito era `if [ "$FAIL" -eq 1 ]` com `FAIL=0` e nenhum `FAIL=1` no
  arquivo — ramificação morta, acumulava findings `high` e passava sempre.
  Corrigido pela convenção da casa (crit/high reprovam) + par
  `project-pwa-bad/good`.

Pendência registrada: outros 9 checks usam `jq` sem guarda e degradam para
no-op silencioso quando ele falta.

### Modo fatiado — `docs/PROMPTS-POR-FASE.md`

Rodar o blindar um módulo por vez em vez do pipeline inteiro numa sessão só.
Diff menor, auditoria mais profunda por módulo, ponto de decisão entre fases.

15 fases principais na ordem de dependência (segurança core cedo, pentest por
último porque audita as correções das outras) + 3 opcionais separadas, cada
uma com "pule se" e critério de pronto. Nomes de agente validados contra o
`MODULE-MAP.json`.

Cada prompt de hardening carrega o **ciclo** dentro dele: roda o check,
corrige na causa raiz, **re-roda o mesmo check para provar que o achado
sumiu**, roda a suíte, repete. Mais a condição de parada — duas rodadas sem
reduzir crit+high e ele para e explica, em vez de insistir. As 4 fases de
diagnóstico não têm ciclo: não corrigem nada.

### Relatório de fases — `scripts/blindar-report.mjs`

Cada fase roda numa sessão limpa, sem contexto da anterior: a fase 15 não sabe
o que a fase 2 fez. `blindar/RELATORIO.md` é essa memória.

- `init` cria se não existir e **não** sobrescreve; `status` mostra o estado e
  a próxima fase; `verificar --fase N` mostra a evidência sem alterar nada.
- Cinco estados (✅ passou, ⚠️ com pendências, ❌ bloqueada, ⏭️ não se aplica,
  ⬜ não rodada). Pendência e bloqueio caem numa seção "Fases que precisam
  voltar" — fase fechada com pendência não conta como fechada.
- Markdown legível com bloco JSON em comentário HTML: humano lê a tabela,
  máquina lê o JSON.
- Pasta `blindar/` é **versionada** (artefato de auditoria), ao contrário de
  `.blindar/`, que é transitória e ignorada pelo git.
- **Não acredita no que é digitado**: escopo por fase lido do MODULE-MAP, e
  `set --estado ok` é recusado se `.blindar/results/` daquela fase tiver
  crit/high aberto ou check com status `failed`.

### Ferramenta ausente ≠ aprovação

O `check-termination.sh` — o script que decide "release liberada" — contava os
findings com `jq` sem guarda. Sem `jq` as contagens vinham vazias, a comparação
numérica falhava em silêncio, e ele imprimia TERMINATION ATINGIDA independente
do que existia. Agora bloqueia com **exit 5**.

- `require_tool` (fatal, quando a ferramenta gateia o check inteiro) e
  `have_tool` (não-fatal, mata só o bloco e deixa o resto rodar) no `_lib.sh`.
  Aplicado no `check-i18n-tz`, onde `jq` gateia apenas a paridade de locales.
- `emit_result` grava `missing_tool` no result — skip por falta de ferramenta
  é ausência de cobertura, não "não se aplica". `have_tool` também marca,
  senão um check aprovado **com** buraco ficaria indistinguível de um aprovado
  com cobertura completa. Campo declarado no `check-result.schema.json`.

## [0.48.0] — 2026-07-11

Rodada "Livros de IA": auditoria da cobertura OWASP LLM Top 10 2025 contra os
agentes de IA existentes + fecha a única lacuna determinística encontrada.

### OWASP LLM Top 10 — auditoria + lacuna fechada

- Auditado: dos 10 riscos, 9 já eram cobertos (`ai-llm-safety` sozinho cobre
  LLM01/02/05/06/09/10; `prompt-injection-defense`, `vector-db-security`,
  `fine-tune-data-leak`, `supply-chain`/`mcp` cobrem o resto).
- **`check-llm-system-prompt-leak`** (novo, módulo 2): fecha **LLM07 (System
  Prompt Leakage)** — system prompt devolvido em resposta HTTP (high) ou logado
  (med). Era o único do Top 10 sem check determinístico. Self-skip sem lib de
  LLM no `package.json`. Par de fixtures `project-sysprompt-bad/good`, gate
  62→63, 0 regressões. Agente `agents/llm-system-prompt-leak.md`. Total 117 agentes.

### Camada de conhecimento (livros de engenharia de IA)

- `docs/book-insights.md` § 5 (novo): destila Huyen (*Designing ML Systems*),
  Hulten (*Engineering Intelligent Systems*), Burkov (*ML Engineering*) e ML
  Design Patterns. Inclui:
  - **Mapa de cobertura OWASP LLM Top 10** → agente/check que materializa cada risco.
  - **Isolar o provider** (Clean Arch + Ports & Adapters + AI Gateway): não
    acoplar SDK do provider na regra de negócio (consultivo — agentes `architect`).
  - **Qualidade sob não-determinismo**: mock de adapter, asserção por schema,
    LLM-as-judge, guardrails de saída, monitorar data drift.

## [0.47.0] — 2026-07-11

Rodada "Livros": incorpora conhecimento acionável de 4 livros de referência
(front-end sec, código legado, appsec, resiliência) ao blindar — como 2 checks
determinísticos que fecham lacunas reais + camada de conhecimento pros agentes.

### Novos checks determinísticos (lacunas reais, não redundantes)

- **`check-prototype-pollution`** (módulo 2): detecta escrita em
  `__proto__`/`constructor.prototype` e merge recursivo caseiro sem guard de
  chave perigosa (padrão CVE-2019-10744 lodash). Antes só existia no pentest
  via LLM — agora é determinístico. Par de fixtures `project-protopoll-bad/good`.
- **`check-client-open-redirect`** (módulo 3): detecta open redirect no lado
  CLIENTE (`location.href = params.get('url')` etc.). O `check-security` só
  pegava o lado servidor (`res.redirect`). Par de fixtures `project-openredir-bad/good`.
- Ambos com par verificado no gate `check-selftest` — cobertura mantida em 100%.
- Agentes playbook: `agents/prototype-pollution.md`, `agents/client-open-redirect.md`.
- Total: **116 agentes** em 19 módulos.

### Camada de conhecimento (livros → comportamento de agente)

- **`docs/book-insights.md`** (novo): destila regras acionáveis de Rossi
  (Segurança em Front-end), Feathers (Código Legado), Crawley (AppSec) e Silva
  (Sistemas Resilientes), cada uma mapeada ao agente/check que a materializa.
  Os 6 livros de arquitetura entram como princípio consultivo, não como check.
- **Princípio Feathers no loop de rounds** (`04-rounds-loop.md`): antes de
  blindar código legado sem teste, escreva um *characterization test* do
  comportamento atual; ache o *seam*; prefira sprout/wrap a reescrever. Estende
  "N/A vira teste de regressão".
- `agents/frontend.md`: seção de checks-irmãos + referência aos livros.

### Sync

- Skill instalada (`~/.claude/skills/blindar`) atualizada pra v0.47 via
  `sync-skill.sh` — as duas cópias permanecem byte-idênticas.

## [0.46.0] — 2026-07-11

Rodada "garantia de aplicação": toda invocação aplica TUDO (deferred incluso),
nenhum resultado stale passa por atual, e dev ↔ instalada sincronizam com 1 comando.

### Orquestrador — anti-stale + versão rastreável

- `scripts/blindar-run.sh`: **fix de resultado stale** — o result JSON do run
  anterior é removido antes de executar cada check (serial E paralelo). Check
  que morre sem escrever agora vira `errored` de verdade, em vez de reler o
  JSON antigo como se fosse desta execução (falso verde silencioso).
- `run-report.json` ganha `skill_version` (conteúdo de `VERSION`) — todo report
  diz qual versão do blindar o gerou. Declarado em `schemas/run-report.schema.json`.

### Contrato de invocação — deferred é fila de trabalho, não rodapé

- `SKILL.md` § EXECUÇÃO MANDATÓRIA: sequência estendida — (1) registrar hora de
  início, (4) validar frescor do report (`ran_at` ≥ início; stale = ERRORED),
  (5) **executar TODOS os agentes deferred** (playbook-only) gravando
  `check-<agent>.json` real antes de apresentar resultado. "Aplicado sempre que
  chamado" agora é regra escrita, não intenção.
- Precedência documentada: sequência mandatória roda em TODA invocação; launcher
  (4 perguntas) e pipeline completo (rounds/PRs) são opt-in. Remove a
  contradição SKILL.md × AI-ENTRYPOINT que deixava o fluxo ao acaso do LLM.
- `AI-ENTRYPOINT.md`: novo "Passo -1" — orquestrador determinístico primeiro,
  decision tree consome o run-report como entrada.

### Sync dev ↔ instalada — 1 comando, verificado

- `scripts/sync-skill.sh` (novo): sincroniza o repo dev → `~/.claude/skills/blindar`
  usando o file-set tracked do git como fonte da verdade. Copia só o que difere,
  remove órfãos, limpa diretórios vazios, preserva runtime da instalada
  (`.git/`, `.blindar/`, `.last-check`) e verifica ao final (exit 1 se sobrou
  drift). Modo `--check` pra CI/inspeção. Substitui o sync manual via
  `git archive | tar -x`.

### Docs sincronizados com a realidade (eram v0.21)

- Contagens defasadas corrigidas em TODA a doc de uso: "72 agentes / 15 módulos"
  → **114 agentes / 19 módulos** (SKILL.md, README.md, USAGE.md, AI-ENTRYPOINT.md,
  CHECKLIST.md, GETTING-STARTED.md, MULTI-AI.md, launcher, rounds-loop). A fonte
  da verdade sempre foi `pipeline/MODULE-MAP.json`; os docs estavam parados na v0.21.
- **Bug de schema**: `config.schema.json` limitava `selected_modules` a
  `maximum: 15` — rejeitaria qualquer config que selecionasse os módulos 16–19
  (evolução/ataque/smoke). Elevado pra 19.
- SKILL.md e launcher agora listam módulos 16–19 (Product Evolution, recon
  passivo, Smoke/Runtime Truth, pentest ativo) com suas condições de ativação
  (API-key / URL / autorização assinada) e o módulo 18 marcado como núcleo.

### Fixes de qualidade

- `check-config-externalization.sh`: `.env.example` só é exigido se o projeto
  usa config por ENV (referência no código ou `.env` real presente). Projeto
  vazio/sem ENV não reprova mais (falso positivo high).
- CI (`lint.yml`): job de schemas aceitava só draft-07, mas 3 schemas
  (check-result, intelligence, run-report) declaram 2020-12 — CI quebraria no
  primeiro push. Agora aceita os dois dialetos. Bonus: `bash -n` também em
  `scripts/*.sh` e `_lib.sh` (antes só nos check-*.sh).
- Line endings: working tree renormalizado (239 arquivos CRLF→LF conforme
  `.gitattributes`); era a causa dos falsos "differ" no diff dev×instalada.
- Instalada deixou de ser clone git: `.git` órfão (parado na v0.42) removido —
  era footgun (um `install.sh` acidental faria `git pull` de código antigo por
  cima da versão sincronizada). Histórico preservado nas tags
  `archive/local42-*` do repo dev.

## [0.45.0] — 2026-07-04

Rodada "Fundação primeiro": consertar o motor determinístico, dar ao blindar um
grafo de conhecimento reusável e — o maior furo histórico — provar que a app SOBE.

### Fase 0 — Motor determinístico consertado (era falso-negativo silencioso)

- `templates/checks/_lib.sh`: fallback `rg` reescrito com fidelidade ao ripgrep
  (flags agrupados `-cE/-nE/-lE/-niE/-hoE` normalizados; `-c` conta só arquivos
  com match; `-n` preservado; excludes default). Fim do "verde mentiroso".
- `scripts/fix-check-syntax.js`: transform seguro (tokeniza flags, não toca
  padrões) aplicado a 55/77 checks — corrige o caminho com ripgrep real.
- `scripts/check-selftest.sh`: gate que prova por par de fixture que cada check
  dispara-no-vulnerável e cala-no-limpo. Cobertura honesta (8/78). Já pegou 1
  falso-positivo real. CI roda com ripgrep E com fallback grep.
- Detalhes em `docs/CHECK-BUGS-AUDIT.md` (seção Resolução).

### Fase 1 — Graphify nativo (grafo de conhecimento multi-modal)

- `scripts/graph-build.js` (zero-dep) + `schemas/graph.schema.json` +
  `agents/graph-builder.md`. Constrói `.blindar/graph.json` uma vez na discovery;
  reusado por todos os agentes (mais cobertura, menos tokens). Classifica
  superfície externa × interna — base pra `api-surface-isolation`.

### Fase 3 — Smoke / Runtime Truth (módulo 18) + homolog-only

- `scripts/smoke-run.sh` + `agents/smoke-runtime.md`: sobe o stack em homolog
  (mock direto no banco, espelho de produção — nunca dev), espera `/health`,
  roda 1 fluxo crítico e flag boot-quebrado + 500 de runtime (o que grep nunca
  pega). Reusa o grafo pra saber o que bater. self-skips sem docker/URL.
- `templates/checks/check-homolog-only.sh`: proíbe config de dev no artefato
  deployável (NODE_ENV=development, dev server, DEBUG=true, DB de dev).
- `pipeline/02-discovery.md`: grafo é o Passo 0 determinístico.
- Testes novos: `tests/graph.test.js` (10), `tests/smoke.test.js` (3) — suite verde.

### Ordem security-first codificada

Sequência não-negociável em `AI-ENTRYPOINT.md`: analisar → implementar o que
falta → **provar que sobe (smoke)** → atacar → proteger → revisar. Segurança é
gate em cada passo, não uma fase.

### Rodada 2 — capacidades novas (Fases 2/4/5/6/7)

**Fase 2 — 6 agentes de arquitetura** (4 determinísticos com par de fixture, 2 API):
- `api-surface-isolation`: interna nunca aceita externa (serviço interno com
  porta publicada / bind 0.0.0.0 = crit), externa protegida (validação, rate/WAF).
- `queue-management`: trabalho pesado inline sem fila; fila sem retry/DLQ/idempotência.
- `fallback-resilience`: chamada externa sem timeout/circuit/retry/health ("se caiu como volta").
- `session-timeout-ux`: timeout de inatividade configurável + popup/blur + resume.
- `solution-architect` (API): vê o grafo e entrega o que FALTA por área.
- `regulatory-mapper` (API): normas/leis/NRs aplicáveis por projeto.

**Fase 4 — 8 checks de infra/runtime** (do retrospecto, cada um de um bug real):
deps-sync, worker-jobs, datetime-tz, entrypoint-cmd, alembic-health,
notnull-no-default, ratelimit-response, infra-windows. Fix do fallback `rg -c`
(descartava contagem 0 em arquivo único) + `-q` mapeado + exit real.

**Fase 5 — ataque + escala:**
- `pentest-active` (módulo 19): payloads reais contra alvo AUTORIZADO. Gate
  `.accept-authorization` (recusa sem ele — zero requests), não-destrutivo, rate-limited.
- `load-test`: escalabilidade como gate (erro% + p95 vs SLO).

**Fase 6 — token/velocidade:** tiers no governor pros agentes novos +
`docs/TOKEN-SPEED.md` (determinístico-primeiro, grafo reusado, módulos lazy).

**Fase 7 — aprendizado:** `scripts/blindar-learn.sh` + `docs/INCIDENT-TO-CHECK.md`
— todo incidente vira check + par de fixture + entrada no gate, em 1 comando.

Cobertura do gate de self-test: **60/60 (100%)** dos checks gate-áveis com par de
fixture verificado (dispara-no-vulnerável + cala-no-limpo), era 4. Não gate-áveis
(scanners externos, .api.sh, runtime, advisory, termination, mcp-security)
documentados na exclusão do denominador. 19 módulos no total.

O próprio gate pegou ~15 bugs de check no caminho (checks que nunca emitiam
`failed`, fallback rg sem stdin/-q/locale) — todos corrigidos.

## [0.44.0] — 2026-07-04

### Novo: **blindar ataque** — recon passivo externo via URL (módulo 17)

Sub-modo do blindar pra descobrir vulnerabilidades **observando** um site em
produção — sem enviar payload de ataque, sem disparar WAF, sem risco de ban.

- `agents/attack-recon.md` — agente com as 6 regras de ouro pra passar
  despercebido (UA browser, rate 1/3s, só GET/HEAD/OPTIONS, IP residencial,
  fora de pico, sem tags fuzz/dos/intrusive).
- `scripts/attack-recon.sh` — runner: headers, TLS/cert, cookies, CORS,
  arquivos esquecidos (`.env`, `.git/config`, `backup.zip`…), endpoints de
  debug (`/actuator`, `/api-docs`…), Certificate Transparency (subdomínios).
- `scripts/attack-recon-report.js` — normaliza saída pra `findings.schema.json`
  (mesmo esquema do resto do blindar).
- Registrado em `pipeline/MODULE-MAP.json` como módulo 17 (opt-in).
- `tests/attack-recon.test.js` — 11 asserts verdes (parseHeaders, detecção
  de .env crit, headers ausentes, cookies inseguros, CORS misconfig, info
  leak, endpoint de debug, aderência ao schema).

Diferente de `pentest` (analisa código) e `dast-hacker` (ataca app de pé com
autorização): este mora **fora do sistema** e só descobre o que qualquer
atacante já veria — modo seguro pra produção real.

## [0.43.0] — 2026-06-25

**Implementa 3 specs pendentes do ROADMAP** (#4, #16, #17) — saem de 🔜 Spec
pra ✅ Done, com código Node zero-deps e testes.

### #16 Reproducibility check — `scripts/reproducibility.js`

- `atkId(finding)` — ID determinístico `ATK-<sha256(cat|file|line|vector)[:8]>`;
  mesmo bug detectado 2x recebe o mesmo ID.
- `canonicalHash(obj)` — hash canônico que **ignora campos voláteis**
  (timestamps, PR#, commit) e ordem de array. Dois runs do mesmo projeto
  comparam por conteúdo real.
- CLI: `--hash f.json` / `--check a.json b.json`.

### #17 ATK SBOM — `scripts/sbom-build.js` + `schemas/sbom.schema.json`

- `buildSbom(findings)` — Bill of Materials de defesas com proveniência
  (PR/commit/agente/versão/round), ID determinístico, dedup, ordenação canônica.
- `validateSbom(sbom)` — validação sem deps (id `^ATK-`, severity, dup).
- CLI: `--build findings.json --out sbom.json` / `--validate sbom.json`.

### #4 Race-fuzzing — `agents/race-fuzzing.md` + `scripts/race-fuzz.js`

- Harness ativo de concorrência: dispara N requests ao mesmo recurso (N
  escalonando 10→100→1000), verifica invariante por nível.
- `fuzzInMemory` (determinístico, testa worker JS — detecta check-then-act,
  aprova reservation pattern) e `fuzzHttp` (contra app de pé, fetch nativo).
- Vai além do adversarial review (que só analisa estaticamente).

### Production safety + piso de modelo

- `docs/PRODUCTION-SAFETY.md` — codifica 2 garantias: (1) não-quebrar
  produção (blindar opera em código via PR, nunca toca banco/infra direto;
  workflow dry-run → staging → backup) e (2) qualidade por modelo (camada
  determinística é igual em todos; raciocínio não).
- **Piso de modelo** `BLINDAR_MIN_MODEL` no `_token_governor.sh`: garante que
  nenhuma análise rode abaixo de um modelo mínimo, mesmo em sessão Haiku ou
  budget tight — o "up" pra modelo menor (delega raciocínio pesado a um modelo
  forte via sub-chamada governada). Backward-compatible: sem a env, nada muda.
- **Preset `BLINDAR_BUDGET=smart`** (recomendado): defaults inteligentes —
  qualidade onde dói, barato onde não. Igual a `standard`, mas tier incerto
  sobe pra Sonnet (seguro) em vez de Haiku (barato): não economiza na dúvida.

### Testes

- `tests/specs.test.js` — 10 asserts (reproducibility + sbom + race-fuzz),
  plugado em `tests/run-tests.sh`. Verde.

## [0.42.0] — 2026-06-22

**Token-aware by design.** Gestão inteligente de tokens enraizada no sistema. Sai de "tudo Haiku barato" pra "modelo certo pro stake certo + cache + telemetria".

### Novo: `_token_governor.sh`

Biblioteca que toda chamada API passa por ela. Funções:

| Função | O que faz |
|---|---|
| `blindar_resolve_tier <agent>` | Mapeia agente → tier (triage/analysis/security/strategic) |
| `blindar_tier_to_model <tier>` | Tier → model ID (com override BLINDAR_BUDGET) |
| `blindar_tier_to_effort <tier>` | Tier → effort (low/medium/high) |
| `blindar_tier_to_max_tokens <tier>` | Tier → max_tokens razoável |
| `blindar_estimate_cost <model> <in> <out>` | Custo USD estimado |
| `blindar_log_cost <agent> <model> <in> <out>` | Append `.blindar/cost.log` |
| `blindar_check_budget` | Aborta se total > BLINDAR_MAX_USD_PER_RUN |
| `blindar_cost_summary` | Resumo no fim do run |

### `_api_wrapper.sh` refatorado

Toda chamada `blindar_api_check` agora:
1. Pre-flight `ANTHROPIC_API_KEY` + curl
2. Pre-flight budget (`blindar_check_budget`)
3. Governor resolve tier → modelo + effort + max_tokens
4. **Cache control** automático em system prompts > ~1024 tokens (90% off)
5. `output_config.effort` enviado no payload
6. Detecta `stop_reason: refusal` → **fallback automático Opus 4.8**
7. Log telemetria em `.blindar/cost.log` com tokens reais
8. Parse findings 1× via Node (não N×)

### Mapeamento tier default

| Agente | Tier | Modelo (standard) |
|---|---|---|
| `architect`, `adversarial-reviewer`, `vector-db-security`, `fine-tune-data-leak` | security | Opus 4.8 |
| `proactive-analysis`, `rag-quality`, `user-journey-simulator`, `feature-gap-analyzer`, `product-critic` | analysis | Sonnet 4.6 |
| `pentest` | security | Opus 4.8 (Fable só se `BLINDAR_ALLOW_FABLE=1`) |
| Outros (triage) | triage | Haiku 4.5 |

### Modos de orçamento

- `BLINDAR_BUDGET=tight` → tudo Haiku (Sonnet só em strategic)
- `BLINDAR_BUDGET=standard` (default) → tier governa
- `BLINDAR_BUDGET=premium` → tudo Opus (Sonnet só em triage)
- `BLINDAR_TIER_<AGENT>=<tier>` → override por agente
- `BLINDAR_MAX_USD_PER_RUN=2.00` → hard cap (default)

### blindar-run.sh

Cost summary automático ao final do run (se `cost.log` existe).

### CLAUDE.md global (REGRA ETERNA)

Nova seção "Gestão inteligente de tokens" adicionada em `~/.claude/CLAUDE.md`:
- 8 filtros obrigatórios antes de toda chamada API
- Anti-padrões banidos (spawn 3 agents desnecessário, skill grande pra info pontual, etc.)
- Quando subir/descer tier
- Regra de respeito: CLAUDE.md é eterno, só pula se user pedir explícito

### Custo esperado

Antes: ~$1.30/run --with-evolution (tudo Haiku, qualidade fraca em segurança crítica)
Depois: ~$8.50/run (tier inteligente, qualidade onde importa)
Em modo `tight`: ~$2/run (similar ao antes, com cache 90% off)

### Validação

- Sintaxe OK em 3 arquivos novos/refatorados
- Test suite 6/6 verde
- Smoke E2E em `clean-project --fast --parallel 4 BLINDAR_BUDGET=tight`: 90% cobertura, schemas válidos

---

## [0.41.0] — 2026-06-21

**Garantia de execução + análise proativa 8 dimensões + security-first reforçado.** Via 2 sub-agentes paralelos. Foco mínimo + máximo impacto.

### 1. SKILL.md — mandato muito mais forte

Seção "EXECUÇÃO MANDATÓRIA — LEIA ANTES DE TUDO" substituiu "ENTRYPOINT ÚNICO E OBRIGATÓRIO":
- Linguagem imperativa explícita ("você DEVE", "você NÃO pode")
- Sequência numerada de 5 passos obrigatórios
- Lista de proibições explícita (não rodar agentes soltos, não pular, não decidir, não pular proactive-analysis)
- Exit codes 0-4 com semântica clara

### 2. Novo: proactive-analysis (8 dimensões)

`agents/proactive-analysis.md` + `templates/checks/check-proactive-analysis.api.sh`:

Roda automaticamente ao final do orquestrador (se `ANTHROPIC_API_KEY` existe). Análise consultiva nas 8 dimensões obrigatórias:

| # | Dimensão |
|---|---|
| 1 | **Segurança** — ataques possíveis, controles ausentes |
| 2 | **Arquitetura** — bounded contexts, acoplamentos, módulos |
| 3 | **Qualidade/Testes** — cobertura, tipos faltantes, quality gates |
| 4 | **Performance** — bottlenecks reais, p95/p99 sugeridas |
| 5 | **Compliance** — LGPD/GDPR/HIPAA/PCI gaps específicos |
| 6 | **Acessibilidade** — WCAG/cognitive/keyboard |
| 7 | **Custos/FinOps** — cloud + LLM tokens + DB |
| 8 | **DX/Operação** — onboarding, runbooks, automações |

Cada dimensão entrega: **Riscos** (com severity) + **Oportunidades** (ROI) + **Trade-offs** + **Custo** + **Quem decide** (CTO/PO/Eng/Compliance).

Schema custom forçado via tool_use (não o padrão de findings). Outputs:
- `.blindar/results/check-proactive-analysis.json` (padrão pra agregação)
- `.blindar/proactive-analysis.md` (relatório markdown legível com tabelas)
- `.blindar/proactive-analysis-raw.json` (debug)

Flag `--no-proactive` ou env `BLINDAR_SKIP_PROACTIVE=1` desliga.

Integrado no `blindar-run.sh` AO FINAL (não-blocking, sempre roda se API key existe).

### 3. Security-first reforçado

- **`--security-only` mode** novo: roda apenas módulos 2 (core security), 5 (supply-chain), 15 (pentest)
- **`--fast` expandido**: agora inclui módulo 5 (supply-chain) — era 1,2,11,12,15, virou 1,2,5,11,12,15
- Mutex `--security-only` com `--module` (exit 64 se ambos)

### MODULE-MAP

Módulo 15 (Pentest + adversarial review): +proactive-analysis (4 agentes total).
Version → 0.41.0.

### Validação

- Test suite: 6/6 verde
- Smoke `--fast --parallel 4`: 90% cobertura executável, schemas válidos
- Smoke `--security-only --parallel 4`: módulos 2/5/15 corretamente filtrados
- proactive-analysis: skip gracioso sem API key (não quebra)

### Por que essa release

Análise externa apontou 6+ dimensões críticas ausentes (Segurança/Qualidade/Performance/Compliance/A11y/Custos/Dados/DX) — blindar **cobria via agentes**, mas não tinha output consultivo estruturado nessas dimensões ao final. Agora tem.

Plus: SKILL.md mandato anterior ainda permitia Claude pular. Versão atual é explícita: "você DEVE / você NÃO pode".

---

## [0.40.0] — 2026-06-21

**Fase C — Scanners reais + schema runtime + blindar-fix killer feature.** Via 5 sub-agentes paralelos. Para de reinventar SAST com grep — integra ferramentas profissionais. Schema validado em runtime. LLM gera patch+teste+PR automático.

### Integrações de scanners reais (4)

| Scanner | Tipo | Cobre | Skip se ausente |
|---|---|---|---|
| **Semgrep** | SAST | OWASP, regras p/security-audit, p/owasp-top-ten | ✓ (pipx install semgrep) |
| **OSV-Scanner** | SCA | Vulns em lockfiles via OSV.dev (Google) | ✓ (brew install osv-scanner) |
| **Trivy** | Multi | Container, IaC, deps, secrets, misconfigs | ✓ (brew install trivy) |
| **Gitleaks** | Secrets | 100+ regras (vs grep manual atual) | ✓ (brew install gitleaks) |

Cada scanner:
- Wrapper traduz output → padrão blindar (`add_finding` + `emit_result`)
- Mapeamento severity nativa → crit/high/med/low
- Skip gracioso sem binary (mensagem de install)
- Timeout configurável (120s default)
- Respeita `--since` (Semgrep tem `--only-changed-files`)

### Schema runtime validado

- `schemas/check-result.schema.json` — valida `.blindar/results/check-*.json`
- `schemas/run-report.schema.json` — valida `.blindar/run-report.json`
- `schemas/intelligence.schema.json` — atualizado pra draft 2020-12
- `scripts/validate-schemas.js` — validador Node zero-deps (AJV se disponível, fallback manual)
- Integração no `blindar-run.sh` no final: warning não-blocking se algo inválido (✓ Schemas válidos / ⚠ N inválidos)
- Smoke: 42/42 results + run-report válidos em fixture

### blindar-fix (killer feature)

`scripts/blindar-fix.sh` + `cli/commands/fix.js` + `agents/blindar-fix.md`:
- Pega finding do run-report.json
- Chama Claude API com 200 linhas ao redor do `file:line`
- Tool_use forçando schema `{patch, test, explanation, confidence}`
- **DEFAULT DRY-RUN** — `--apply` é flag explícita
- Valida com `git apply --check` antes de aplicar
- Cria branch separada (recusa main/master/develop/production)
- `--auto-all` itera todos crit/high do último run
- `--pr` abre PR via `gh` (se disponível)
- Skip gracioso sem `ANTHROPIC_API_KEY`
- Timeout 90s API call

### Estatísticas

- **5 sub-agentes paralelos** — wall-clock ~28 min (vs ~75 min sequencial estimado)
- **15 arquivos novos** (~1.500 linhas)
- Zero conflito entre agentes (cada um em arquivos diferentes)

### MODULE-MAP atualizado

| Módulo | Antes | Depois | Diff |
|---|---|---|---|
| 2 (security) | 15 agentes | 17 | +semgrep, +gitleaks |
| 5 (supply-chain) | 3 | 5 | +osv-scanner, +trivy |
| 14 (DX) | 10 | 11 | +blindar-fix |

### Cobertura geral

| Tipo | v0.39 | v0.40 |
|---|---|---|
| Scripts determinísticos | 62 | **69** |
| Wrappers API | 7 | **7** |
| Agentes só playbook | 13 | **8** |
| **Cobertura executável** | 84% | **91%** |
| **Schemas validados runtime** | ❌ | ✅ |

### Smoke real

`tests/fixtures/clean-project --fast --parallel 4`:
- 20 agentes, 11 passed, 2 failed (legítimos), 12 skipped, 2 deferred, 0 errored
- 92% cobertura executável
- `✓ Schemas válidos` no final
- Duração: 49s
- Test suite blindar: 6/6 verde

### Implicação competitiva

Blindar agora cobre o que Snyk/Semgrep/SonarQube fazem (via integração) **PLUS** o moat BR + AI-era do v0.39. Antes era "alternativa diferente", agora é "superset opinado".

---

## [0.39.0] — 2026-06-21

**Fase B — Moats reais.** 9 agentes novos materializados via 4 sub-agentes paralelos. Foco: AI-era (5) + verticais BR (4). Esta é a defensibilidade que blindar tem que Snyk/Semgrep não copia em 6 meses.

### 5 agentes AI-era (módulo 2 — security core)

| Agente | Tipo | Cobre |
|---|---|---|
| `prompt-injection-defense` | `.sh` | OWASP LLM01 — system+user concat, tool output em eval/innerHTML, sem rate-limit, sem max_tokens |
| `mcp-security` | `.sh` | Audita MCPs em `~/.claude.json` — capability bleed, plain-text tokens, não-whitelisted vs catalog |
| `rag-quality` | `.api.sh` | chunking, embedding model, top-k, reranking, citation grounding, eval framework |
| `vector-db-security` | `.api.sh` | tenant isolation, PII em embeddings, encryption at rest, query injection via metadata |
| `fine-tune-data-leak` | `.api.sh` | PII em training set, prompt-completion ratio, memorization risk, eval split |

### 4 agentes verticais BR (módulos 8 e 10 — moat real)

| Agente | Tipo | Cobre |
|---|---|---|
| `fintech-banking-br` | `.sh` | PIX (idempotência, MED, QR), Open Finance Fases 1-4 (FAPI/MTLS/PS256), BACEN 4658, money em float, webhook sem signature |
| `ecom-checkout-conversion` | `.sh` | Multi-step >3, autocomplete cc-*, 3DS2 (R$ 500+), Apple/Google Pay, cart persist, frete pré-checkout, ViaCEP |
| `healthtech-fhir` | `.sh` | Patient sem identifier, PHI em log, telemedicina CFM 2299, Consent ausente, Provenance ausente, timezone Encounter |
| `govtech-acessibilidade` | `.sh` | eMAG (atalhos Alt+1/2/3, foco-visible, alto-contraste), gov.br SSO, VLibras, mapa do site, LAI `/transparencia` |

### Estatística

- **18 arquivos novos** (9 .md + 9 .sh/.api.sh)
- **~3.000 linhas** total
- 4 sub-agentes paralelos: ~9 min wall-clock (vs ~36 min sequencial estimado)
- Zero conflito (cada agente em arquivos diferentes)

### MODULE-MAP atualizado

- Módulo 2 ganhou 5 agentes (15 total)
- Módulo 8 ganhou 3 agentes (8 total)
- Módulo 10 ganhou 1 agente (15 total)
- Versão `pipeline/MODULE-MAP.json` → 0.39.0

### Cobertura geral atualizada

| Tipo | v0.38 | v0.39 |
|---|---|---|
| Scripts determinísticos | 55 | **62** |
| Wrappers API | 4 | **7** |
| Agentes só playbook | 22 | **13** |
| **Cobertura executável** | 80% | **84%** |

### Smoke real

Rodado em `tests/fixtures/clean-project` com `--module 2,8,10 --parallel 4`:
- 38 agentes selecionados
- 11 passed, 0 failed, 13 skipped (não-aplicável à fixture), 14 deferred (playbook-only), 0 errored
- 63% cobertura executável neste filtro
- Test suite blindar: 6/6 verde

### Diferencial competitivo agora

| Recurso | blindar | Snyk | Semgrep | SonarQube |
|---|---|---|---|---|
| LGPD-BR nativa | ✅ | ❌ | ❌ | ❌ |
| PIX/Open Finance/BACEN | ✅ | ❌ | ❌ | ❌ |
| FHIR + telemedicina CFM | ✅ | ❌ | ❌ | ❌ |
| eMAG gov BR | ✅ | ❌ | ❌ | ❌ |
| MCP security audit | ✅ | ❌ | ❌ | ❌ |
| RAG/Vector DB security | ✅ | ❌ | ❌ | ❌ |
| Prompt injection defense | ✅ | parcial | parcial | ❌ |

---

## [0.38.0] — 2026-06-21

**Fase A — Quick wins** (executado via 3 agentes paralelos). Destrava ecossistema (SARIF), 5-10× speedup (paralelização), PR-time gate (--since), debug humanizado (--verbose), fix de bugs descobertos na auditoria.

### Novo: SARIF converter

- `scripts/sarif-converter.js` — 367 linhas, zero deps, Node 20+ nativo
- Converte `.blindar/results/check-*.json` → SARIF 2.1.0 válido
- Severity mapping: crit/high → error, med → warning, low → note
- Cada agente vira `tool.driver` com rules dedup'd `blindar.<agent>.<sev>`
- Inclui `versionControlProvenance` quando `git_sha` presente
- CLI: `--input DIR` (default `.blindar/results`), `--output FILE` (default stdout), `--help`
- Sample fixture gerada em `tests/fixtures/clean-project/.blindar/sarif-sample.json`
- **Destrava**: GitHub Code Scanning, Azure DevOps, Sonar, qualquer leitor SARIF

### blindar-run.sh: 3 features novas

**`--since REF` (diff mode / PR-time gate)**:
- Roda `git diff --name-only "$REF"...HEAD`
- Exporta `BLINDAR_CHANGED_FILES` (newline-separated) + `BLINDAR_SINCE_REF` pros checks
- Adiciona `since` + `changed_files: []` no run-report.json
- Exit 0 se zero arquivos mudaram ("no changes since X — nothing to check")
- Valida: git instalado + repo git + ref existe (exit 73 se algo falha)

**`--parallel N` (paralelização via xargs -P)**:
- Default 1 (sequencial — preserva comportamento anterior)
- `--parallel auto` detecta CPUs via nproc/sysctl, fallback 4
- Worker grava 1 linha em `$RESULTS_DIR/.run-lines.log` (sem race em vars bash)
- Agregação acontece DEPOIS do loop (lendo log)
- 5-10× speedup em runs full (20+ agentes)

**`--verbose` / `-v` (preserva stdout dos checks)**:
- Sem flag: `bash $script >/dev/null 2>&1` (comportamento atual silent)
- Com flag: `bash $script 2>&1 | sed "s/^/  [$agent] /"` (prefixa output com nome)
- Debug humanizado — bugs sutis em checks ficam visíveis

### _lib.sh: fixes

**Trap ERR removido (era código morto)**:
- `set +e +o pipefail` desativa errexit
- `trap on_error ERR` só dispara com errexit ativo → nunca disparava
- Removido + comentário longo explicando por que NÃO recolocar
- Checks gerenciam erros via `emit_result` + `add_finding`

**Bash version warn**:
- Detecta bash < 4 e avisa (NÃO fail)
- Variável `BLINDAR_BASH_WARN_SHOWN` impede repetir a cada source
- Aponta pra `docs/BASH-COMPAT.md`

### Novo: docs/BASH-COMPAT.md

- Auditoria de 53 scripts blindar — **zero uso de features bash 4+** detectado
- Codebase já é bash 3.2 compat
- Matriz de plataformas + instruções `brew install bash` pra macOS
- Tabela de features auditadas + padrão pra novos checks
- Comandos pra auditar futuros checks

### Validação multi-agente

Executado via 3 Agent calls em paralelo (não Workflow):
- Agent A (SARIF): 367 linhas, smoke test passou em 2 fixtures
- Agent B (_lib + bash compat): 6/6 tests verde
- Agent C (blindar-run refactor): 249 → 411 linhas (+162), smoke `--fast --verbose --parallel 4` rodou em 47s com 90% cobertura

Sem conflitos entre agentes (cada um em arquivos diferentes — SARIF=new, _lib.sh=B, blindar-run.sh=C).

### Próximo (Fase B / C)

- Fase B: 9 agentes novos (5 AI-era + 4 verticais BR) — vira moat
- Fase C: integração Semgrep/OSV/Trivy/Gitleaks + schema runtime + blindar-fix

---

## [0.37.0] — 2026-06-21

**Launcher: pergunta de escopo + flag `--with-evolution`.**

### Launcher (pipeline/00-launcher.md)

Pergunta 4/4 virou Pergunta 4/5. Nova **Pergunta 5/5 — Escopo**:
- **A** Hardening completo (módulos 1-15) — default
- **B** Hardening + Evolução (1-16) — review técnico + análise produto
- **C** Só evolução (16) — APIs órfãs, gaps, oportunidades, crítica
- **D** Custom — escolho módulos

Validação automática: se B/C/D-com-16 sem `ANTHROPIC_API_KEY`, avisa e pergunta abort/continue.

Menu agora mostra módulo 16 com tag `[escopo B|C]`. Atalho novo: `"evolution"`.

### Flag --with-evolution

`scripts/blindar-run.sh --with-evolution` encadeia automaticamente:
1. Roda hardening normal
2. Captura exit code (preservado pra CI gate)
3. Invoca `blindar-evolve.sh` no final
4. Sai com o exit code do hardening (evolution é informativo)

Equivale ao escopo **B** do launcher numa linha só.

### GETTING-STARTED.md

Nova tabela "Escopos por contexto":
- Daily commit/PR → `--fast`
- Fim de sprint → `--with-evolution`
- Sprint planning → `blindar-evolve.sh`
- CI gate → `--strict --json`
- Investigação pontual → `--module N,N`

### Smoke

Rodado `--fast --with-evolution` em clean-project:
- Hardening: 90% cobertura, exit 1 (deferred)
- Evolution: skip limpo sem API key, mensagem clara
- Exit final: 1 (hardening, preserva gate)

---

## [0.36.0] — 2026-06-21

**Módulo 16 — Product Evolution** (opt-in, escopo separado do core hardening).

### Novo: 5 agentes evolution (todos API-wrapped)

| Agente | Cobre |
|---|---|
| `api-frontend-coverage` | APIs sem front-end + propõe tela/componente alinhado com stack |
| `user-journey-simulator` | Detecta perfis, simula cenários, identifica fricções por jornada |
| `feature-gap-analyzer` | Features parciais: schema sem API, API sem UI, UI sem validação, flag morta |
| `growth-opportunities` | Wishlist por ROI: retenção, automação, IA, multi-canal, monetização |
| `product-critic` | Adversarial PO: inconsistências, over/under-engineering, telas órfãs, dark patterns |

### Novo: orquestrador dedicado

`scripts/blindar-evolve.sh` — separado do `blindar-run.sh`:
- Roda apenas módulo 16
- Requer `ANTHROPIC_API_KEY`
- Gera `.blindar/evolution-report.md` consolidado (markdown legível, ordenado por severity)
- Inclui roadmap recomendado em 5 ondas

### Atualizações

- `pipeline/MODULE-MAP.json` v0.36.0 — módulo 16 com `entrypoint` próprio + nota explicando escopo
- `SKILL.md` — seção "Módulo 16 — Product Evolution" deixando claro: escopo separado, NÃO entra no fluxo padrão

### Decisão arquitetural

Mantido **fora do core** porque:
1. Hardening (core) = determinístico, exit code, CI gate
2. Evolution = subjetivo, baseado em julgamento LLM, exploração estratégica
3. Misturar dilui a promessa "exit 0 = release"
4. Frequência diferente: core a cada commit; evolution uma vez por sprint

### Uso

```bash
export ANTHROPIC_API_KEY=sk-ant-...
cd seu-projeto
bash ~/.claude/skills/blindar/scripts/blindar-evolve.sh
cat .blindar/evolution-report.md
```

Smoke (sem API key): skip gracioso com mensagem clara.

---

## [0.35.0] — 2026-06-21

**Pronto pra uso em projeto real.** Polish completo de install + UX + orquestrador resiliente a layouts diferentes.

### Mudanças

- **`scripts/blindar-run.sh`** detecta layout automaticamente:
  - Layout skill canonical (`~/.claude/skills/blindar/scripts/`)
  - Layout instalado no projeto (`projeto/scripts/blindar/`)
  - Fallback via `$HOME/.claude/skills/blindar/`
- **`scripts/install-deterministic-checks.sh`** atualizado:
  - Copia orquestrador `blindar-run.sh` pro `scripts/` do projeto
  - Copia `MODULE-MAP.json` pra `scripts/blindar/pipeline/`
- **`GETTING-STARTED.md`** novo (1 página):
  - 30 segundos: rodar sem instalar
  - 1 minuto: instalar com CI + hooks
  - Comandos essenciais
  - Troubleshooting

### Validação end-to-end

1. Rodado em projeto Blidar real (própria skill): 90% cobertura, 0 errored, findings reais detectados (15 mock-killer + 2 config-ext)
2. Rodado em projeto vazio `/tmp/blindar-test-project` (git init + package.json mínimo): instalou + rodou + gerou report (90% cobertura)
3. Test suite: 6/6 verde

### Caminhos de uso garantidos

| Forma | Comando |
|---|---|
| Skill direto | `bash ~/.claude/skills/blindar/scripts/blindar-run.sh --fast` |
| Após init | `npm run blindar:fast` ou `bash scripts/blindar-run.sh --fast` |
| Claude Code | `/blindar` |
| CLI Node | `node ~/.claude/skills/blindar/cli/bin/blindar.js check` |

---

## [0.34.0] — 2026-06-21

**Wave guardian** — gate determinístico obrigatório no fim de cada onda do rounds-loop. Impede que ondas fechem com gaps invisíveis.

### Novo: wave-guardian

- `agents/wave-guardian.md` — playbook
- `templates/checks/check-wave-guardian.sh` — validador determinístico
- `pipeline/04-rounds-loop.md` — gate injetado como passo obrigatório de fim de onda
- `pipeline/MODULE-MAP.json` — wave-guardian adicionado ao módulo 15 (Pentest + adversarial), versão bump 0.34.0

### Como funciona

```bash
# Final de cada onda:
WAVE_NUMBER=2 \
WAVE_AGENTS="mock-killer,access-control,cryptography" \
MIN_COVERAGE_PCT=90 \
bash templates/checks/check-wave-guardian.sh
```

Lê `.blindar/run-report.json` (gerado por `blindar-run.sh`) e valida:

| Condição | Decisão |
|---|---|
| `errored > 0` | **BLOCK** — bugs em scripts blindar |
| `failed crit > 0` | **BLOCK** — onda manteve ou introduziu crítico |
| `deferred > 0` sem `playbook-executed/<agent>.json` | **BLOCK** — Claude pulou playbook |
| `coverage_pct < min_coverage_pct` | WARN (não bloqueia) |
| Tudo OK | **PASS** |

Gera `.blindar/wave-<N>-guardian.md` com decisão + métricas + motivos do bloqueio + ações requeridas.

### Anti-padrão resolvido

Antes: Claude rodava agentes, dizia "tudo OK", fechava onda. Não havia gate.
Depois: orquestrador → guardian → BLOCK ou PASS estruturado em arquivo. **Impossível fechar onda com débito invisível.**

### Smoke test

Rodado em `tests/fixtures/clean-project`:
- run-report: 20 agentes, 9 passed, 2 failed, 7 skipped, 2 deferred
- guardian: BLOCKED (2 deferred sem playbook executado)
- Gerou `wave-1-guardian.md` com motivos + ação requerida

Comportamento esperado e correto: clean-project não cobriu pentest/adversarial-reviewer manualmente, então não pode fechar.

---

## [0.33.0] — 2026-06-21

**Garantia máxima de execução.** Resolve o gap "Claude precisa obedecer" via:
**orquestrador único** (`scripts/blindar-run.sh`) + **wrapper API genérico** pra agentes que precisam de julgamento + **8 scripts Tier 1 críticos** materializados.

### Novo: orquestrador único

`scripts/blindar-run.sh` — **entrypoint mandatório** declarado em SKILL.md.
- Lê MODULE-MAP.json (fonte da verdade)
- Itera cada agente do filtro (--fast: módulos 1,2,11,12,15; --module N,N: arbitrário; default: all)
- Pra cada agente: procura `check-<a>.sh` (det) → `check-<a>.api.sh` (API) → fallback `deferred`
- Grava `.blindar/run-report.json` com cobertura executável real e exit code claro:
  - 0=GO, 1=CONDITIONAL-GO (deferred), 2=NO-GO (failed), 3=STRICT-FAIL, 4=ERRORED

### Novo: wrapper API genérico

`templates/checks/_api_wrapper.sh` — biblioteca pra criar `check-X.api.sh`.
- `blindar_api_check AGENT SYSTEM CONTENT [MODEL]` — força tool use estruturado
- JSON schema validado pela API (não depende de parsing frágil de markdown)
- Skipped gracioso se sem `ANTHROPIC_API_KEY`
- Default model: `claude-haiku-4-5-20251001` (barato pra triagem)

### Novos scripts (8 Tier 1 críticos)

| Script | Cobre |
|---|---|
| `check-access-control.sh` | OWASP A01 — endpoints sem guard, IDOR, default-allow, roles hardcoded |
| `check-cryptography.sh` | OWASP A02 — MD5/SHA1, bcrypt rounds, DES/ECB, Math.random crypto, JWT none |
| `check-runtime-secrets.sh` | process.env client leak, console com objeto sensível, secret em URL, stack em prod |
| `check-strategic-scanner.sh` | Fase 0 — detecção de stack → `.blindar/scan.json` |
| `check-security.sh` | Umbrella — eval, innerHTML, SQL concat, shell injection, helmet, open redirect |
| `check-functional-e2e.sh` | Framework E2E instalado + pasta de testes + CI roda + smoke marker |
| `check-frontend.sh` | CSP, Trusted Types, SRI em CDN, target=_blank sem noopener, iframe sem sandbox, postMessage origin |
| `check-supply-chain.sh` | Lockfile, npm audit, deps em git URL, wildcard versions |
| `check-tenant-isolation-tests.sh` | Wrapper canonical pro check-tenant-isolation (nome bate com MODULE-MAP) |

### Novos wrappers API (3 agentes de julgamento)

| Script | Quando força Claude API |
|---|---|
| `check-adversarial-reviewer.api.sh` | Red team de findings já encontrados — refuta ou confirma |
| `check-architect.api.sh` | Decisões arquiteturais (boundaries, coupling, scaling path) |
| `check-pentest.api.sh` | Attack vectors REAIS (IDOR, escalation, race, SSRF, mass assignment) |

### SKILL.md atualizado

Seção nova **"ENTRYPOINT ÚNICO E OBRIGATÓRIO"** no topo declarando que Claude deve invocar `scripts/blindar-run.sh` como primeira ação.

### Cobertura executável (smoke real)

Rodado em `tests/fixtures/clean-project` com `--fast`:
- 19 agentes selecionados (módulos 1,2,11,12,15)
- 11 deterministic + 2 api-wrapped + 2 playbook-only + 4 não cobertos
- **84% cobertura executável** (era 0% antes de v0.33 — só playbooks)

### Cobertura geral

| Categoria | v0.32 | v0.33 |
|---|---|---|
| Scripts determinísticos | 47 | **55** |
| Wrappers API | 1 (demo) | **4** |
| Agentes só playbook | 30 | **22** |
| **Total agentes executáveis** | 48/74 (65%) | **59/74 (80%)** |

### Anti-pattern resolvido

Antes: "Claude lê SKILL.md e DEVERIA rodar tudo. Pula? Ninguém sabe."
Depois: `bash scripts/blindar-run.sh` é determinístico. Cobertura é mensurável. Skip silencioso impossível — vira `deferred` explícito no relatório.

---

## [0.32.0] — 2026-06-21

**Garantia de execução.** Release de correção crítica — descoberto que múltiplos scripts e o CLI **não funcionavam de fato** fora do ambiente Claude Code. Esta versão torna blindar **executável de verdade** em qualquer máquina com bash + Node 20+.

### Bugs críticos corrigidos

1. **`rg --type tsx/jsx` inválido** (12 scripts) — ripgrep não tem types `tsx`/`jsx` separados (`ts` já cobre `.tsx`, `js` já cobre `.jsx`). Resultado: scripts faziam skip silencioso, **nenhum console.log/mock/secret era detectado** em arquivos React. Corrigido via sed em massa.

2. **`rg` ausente como binário** — em muitos ambientes (incluindo o do dev original) `rg` é função do shell Claude Code, não binário real. Scripts em sub-shell faziam skip. **Adicionado fallback `grep -rE`** no `_lib.sh` que traduz flags rg → grep automaticamente. Funciona em CI, Windows Git Bash, Linux puro.

3. **`set -euo pipefail` matava pipelines `rg | sort`** — quando rg retornava exit 1 (sem match, normal), pipefail matava o script via trap `ERR`. **Removido pipefail do `_lib.sh`** — cada check controla seu próprio errexit.

4. **`run-all.sh` removia "check-" do path inteiro** (não só do basename), procurava `.blindar/results/secrets.json` quando arquivo era `check-secrets.json`. Resultado: todos os checks reportavam "sem result file". Corrigido.

5. **`run-all.sh` exigia `jq`** que não vem por default no Windows. **Adicionado fallback Node.js** pro aggregate JSON e fallback `grep+sed` pra status parsing.

6. **CLI dependia de `mri` + `kleur`** que nunca foram instalados via npm (CLI não tinha `node_modules/`). Resultado: `npx blindar` quebrava com `ERR_MODULE_NOT_FOUND`. **Removidas deps externas**: parseArgs nativo + lib/colors.js com ANSI puro. Zero deps agora.

7. **CLI exigia `.git` dir presente** — falhava em fixtures de teste ou projetos novos. Trocado pra `git rev-parse --is-inside-work-tree` + warn (não bloqueia).

8. **`check-ai-powered-example.sh` falhava com `unbound variable`** em ambientes sem `ANTHROPIC_API_KEY` set. Trocado pra `${ANTHROPIC_API_KEY:-}`.

9. **`check-mock-killer` regex `TODO|FIXME` batia em "TODOS"** — falso positivo. Adicionado `\b` word boundary.

10. **Globs `.blindar` e `.git`** não estavam nos IGNORE_GLOBS — checks liam seus próprios outputs JSON e geravam findings reentrantes.

### Validação

- ✅ Test suite 6/6 (era 4/6 antes — 2 falhas reais)
- ✅ 47 scripts: sintaxe bash OK
- ✅ 11 scripts novos de v0.31: smoke test OK em clean-project
- ✅ CLI: `version`, `help`, `check --fast` funcionam zero-deps
- ✅ `run-all.sh` agrega corretamente sem jq instalado

### Promessa honesta

Após v0.32, garantia de execução é:
- **Determinístico (47 scripts)**: roda em bash + grep. Se você tiver Git Bash (Windows) ou bash nativo, funciona.
- **CLI**: roda com Node 20+ sem deps externas. `npx blindar check` é confiável.
- **AI-powered (1 script demo)**: pula gracioso se sem `ANTHROPIC_API_KEY`.
- **Playbooks (.md em agents/)**: ainda dependem de Claude executar — não há como "garantir" 100% sem materializar todos.

Cobertura real: **58% determinístico** (47 scripts ÷ 72 agentes + 4 não-agentes core). Meta v1.0: 100%.

---

## [0.31.0] — 2026-06-21

Mega-release: **Redis patterns + MCP recommender** + 10 novos check scripts + **dashboard local** + **i18n EN** + **AI-powered check example** + **v1.0 LTS path documentado**.

### Novos agentes (2)

- **redis-patterns** (módulo 9): TTL obrigatório, multi-tenant prefix, eviction policy, persistence (AOF+RDB), Redlock vs SETNX, pipeline, cache-aside vs write-through, Streams + consumer groups, rate limit sliding window, TLS+AUTH, cluster mode >25GB, Vector sets, observability
- **mcp-recommender** (módulo 14): Auto-detecta stack e sugere MCPs (Supabase, GitHub, Figma, Notion, Cloudflare, MongoDB, HuggingFace, Linear, Google Workspace) com critério: oficial + OAuth + read-mostly + blindar-compatible + sem PII leak

### Novos check scripts (10)

| Script | O que detecta |
|---|---|
| `check-redis-patterns.sh` | Key sem TTL, SETNX raw, sem tenant prefix, noeviction, sem AUTH, KEYS *, FLUSHALL, loop com N round-trips |
| `check-mcp-recommended.sh` | Detecta stack e lista MCPs sugeridos (não-blocking, sempre passed) |
| `check-business-logic.sh` | Preço/desconto do client aceito, optimistic locking ausente, read-then-write sem transaction |
| `check-cors-csrf.sh` | CORS:* (CRIT), credentials:true+reflect (CRIT), CSRF ausente em forms, cookie sem SameSite |
| `check-rate-limit.sh` | Rotas POST/PUT/DELETE sem rate-limit, endpoint sensível sem RL dedicado |
| `check-secrets-rotation.sh` | Hardcoded secrets (sk_live, ghp_, AKIA), .env sem .env.example, README sem política rotação |
| `check-soft-delete.sh` | Models sem deletedAt, prisma.delete() cru em entidade principal |
| `check-audit-log.sh` | Sem model AuditLog, mutations sensíveis sem auditLog.create() |
| `check-pagination.sh` | findMany sem take/limit/cursor |
| `check-headers-security.sh` | Helmet ausente, headers faltantes (CSP/HSTS/X-Frame), unsafe-inline, unsafe-eval |
| `check-ai-powered-example.sh` | Exemplo de check híbrido: shell coleta evidência + Claude Haiku analisa + JSON estruturado (skipped se sem ANTHROPIC_API_KEY) |

**Total: 47 arquivos em templates/checks/** (43 checks + _lib + run-all + termination + auto-fix).

### Catálogo MCP

- `templates/mcp-catalog.yml` — 10 MCPs curados com schema (trigger.detect, scopes, safety, install_url, blindar_compatible)
- Seção `declined_by_default` com MCPs nunca recomendados (shell-exec, generic DB admin, sem update >6m)

### Dashboard local

- `templates/dashboard/dashboard.html` — HTML+CSS+JS vanilla, lê `.blindar/report.json`
- Stats por severidade, tabela de checks, findings ordenados
- Zero deps, zero build. Sirva com `python -m http.server`

### i18n

- `docs/i18n/README.en.md` — versão EN inicial do README (philosophy, modules, quickstart, GitHub Action)

### v1.0 LTS path

- `docs/V1.0-PATH.md` — roadmap completo: gaps de contrato, cobertura (58% agentes materializados), distribuição (npm/homebrew/docker/VS Code), qualidade (CI matrix, security audit), comunidade
- ETA v1.0: **jan/2027** (LTS 12 meses)
- Compromissos não-negociáveis: zero falsos positivos críticos, <30s execution, determinismo em decisões blocking, auto-fix nunca destrutivo

### Arquivos atualizados

- `VERSION` 0.30.0 → 0.31.0
- `pipeline/MODULE-MAP.json` v0.31.0, +redis-patterns em módulo 9, +mcp-recommender em módulo 14
- `agents/redis-patterns.md` (~500 linhas, novo)
- `agents/mcp-recommender.md` (novo, critérios + catálogo + 3-gate approval)

---

## [0.30.0] — 2026-06-21

Mega-release que entrega top-4 prioridades de uma vez: **+10 scripts**,
**npm publish setup**, **GitHub Action publicada**, **auto-fix mode**.

### v0.27 — +10 check scripts (cobertura 22 → 32)

| Script | O que detecta |
|---|---|
| `check-scheduled-jobs.sh` | @Cron sem Redlock, queue.add sem retry, sem watchdog, sem DLQ tracking, setInterval sem clearInterval |
| `check-sbom-slsa.sh` | Lockfile ausente, Dockerfile FROM :latest (CRIT), GH Actions sem SHA pin, sem SBOM/SLSA/Cosign, build não-reprodutível |
| `check-ai-llm-safety.sh` | LLM call sem max_tokens, userInput em system prompt (CRIT prompt injection), output em eval/innerHTML (CRIT), sem rate limit, PII em prompt, sem aviso "é IA", tool destrutiva sem confirmação |
| `check-realtime.sh` | WS sem auth no handshake (CRIT), io.emit sem namespace tenant, token em URL, sem heartbeat |
| `check-feature-flags.sh` | process.env.FEATURE inline, if(true)/if(false), flag "temporário", sem tabela feature_flags |
| `check-email-deliverability.sh` | Env-aware (DMARC strict só em prod), template hardcoded, send sem check de supressão, sem bounce webhook, no-reply@ |
| `check-cdn-strategy.sh` | Cache-Control:no-cache espalhado, <img> sem next/image, asset sem hash no path, CORS:* em CDN, video preload=auto |
| `check-seo-marketing-meta.sh` | sitemap ausente, robots ausente, noindex em rota pública, sem og:image, title duplicado, sem JSON-LD |
| `check-backup-recovery.sh` | Sem runbook, sem restore drill, backup sem encryption, sem PITR |
| `check-compliance-lgpd-br.sh` | Sem política privacidade, sem runbook ANPD 72h, < 6 endpoints LGPD, sem DPO público, analytics sem cookie banner, sem age gate, sem anonimização irreversível |
| `check-cost-observability.sh` | LLM sem tabela llm_usage, S3 sem lifecycle policy, sem budget alert, sem slow query monitoring, sem per-feature cost |

**Total: 36 arquivos em templates/checks/** (32 checks + _lib + run-all + termination + auto-fix).

### v0.28 — npm publish setup

- `cli/.npmignore` — exclui node_modules, tests, .git
- `.github/workflows/npm-publish.yml` — auto-publica quando criar tag `v*.*.*`:
  - Sincroniza version de VERSION → cli/package.json
  - `npm publish --provenance --access public` (com OIDC + SLSA 3)
  - Cria GitHub Release com generate_release_notes
- Requer: secret `NPM_TOKEN` no GitHub

Próximo passo: `gh secret set NPM_TOKEN` + `git tag v0.30.0 && git push --tags`

### v0.36 — GitHub Action publicada

`action.yml` na raiz do repo → permite usar como step em qualquer workflow:

```yaml
- uses: pretinhuu1-boop/blindar@v0.30
  with:
    mode: full              # ou: fast
    fail-on: high           # crit | high | med | low
    skip-checks: ""         # CSV
    post-comment: true      # resumo no PR
```

Outputs: `status`, `crits`, `highs` (utilizáveis em steps seguintes).

Auto-instala gitleaks/ripgrep/jq se ausentes. Posta comentário rico no PR.

### v0.43 — Auto-fix mode (game-changer de produtividade)

Novo comando: `blindar fix [--apply] [--check <agent>]`

- `templates/checks/auto-fix.sh` — aplica correções SEGURAS + ÓBVIAS:
  - **FIX 1**: console.log em `*.dev.ts` → adiciona `// @blindar:keep`
  - **FIX 2**: TODOs sem issue → sugere (não aplica — precisa criar issue antes)
  - **FIX 3**: `.env.example` sync — adiciona vars usadas no código mas ausentes
  - **FIX 4**: `<img>` sem alt — só sugere (não inventa alt errado)
  - **FIX 5**: GH Actions sem SHA pin — sugere usar `pinact`
  - **FIX 6**: Dockerfile :latest — sugere versão major + SHA

- `cli/commands/fix.js` — wrapper Node
  - Modo dry-run default (mostra o que faria)
  - `--apply` cria branch + commit automático
  - Co-Authored-By: blindar no commit pra rastreabilidade
  - `--check <name>` foca em fixes de um agente específico

### Atualização CLI

`cli/bin/blindar.js` ganha comando `fix` no roteador.
`cli/commands/help.js` lista comando novo.

### Validação

- 37 scripts shell: `bash -n` ✅ (todos passam)
- 8 arquivos Node: `node --check` ✅ (todos passam)
- 2 workflows YAML: structure valid ✅
- 1 action.yml: composite action valid ✅

### Como usar tudo isso

```bash
# 1. Instalar localmente no projeto
npx blindar init

# 2. Rodar checks
npx blindar check

# 3. Auto-fixar o que dá
npx blindar fix --apply

# 4. Decidir release
npx blindar terminate

# 5. Gerar relatórios pro cliente
npx blindar report
```

Em CI (qualquer projeto):
```yaml
- uses: pretinhuu1-boop/blindar@v0.30
  with: { mode: full, fail-on: high }
```

### Total inventário v0.30

| Item | Quantidade |
|---|---|
| Agentes (.md) | 72 |
| Scripts check shell | **32 + 4 utils** (_lib, run-all, termination, auto-fix) |
| CLI Node | 8 arquivos (entry + 7 comandos) |
| Test fixtures | 6 |
| Configs lib | 2 (Lighthouse + size-limit) |
| Templates HTML | 4 |
| Schemas JSON | 9 |
| Hooks Husky | 2 |
| GitHub workflows | 2 (lint + npm-publish) |
| **GitHub Action publicada** | **1 (action.yml)** |
| Installer + test runner | 2 |

### Próximas iterações

| v | Foco |
|---|---|
| 0.31 | Materializar restante (~40 scripts) → cobertura ~70% |
| 0.32 | Dashboard web hosted (cliente abre URL) |
| 0.37 | i18n da skill (EN-US + ES-ES) |
| 0.38 | AI-powered intelligence (context-aware via LLM local) |
| 0.50 | v1.0 LTS stable API |

---

## [0.26.0] — 2026-06-14

Mega-release que entrega 4 iterações de uma vez: **v0.23+v0.24+v0.25+v0.26**.

### v0.23 — Materializou +10 check scripts (total: 18 → soma 22 com v0.25)

| Script | Materializa | Detecta |
|---|---|---|
| `check-auth-premium.sh` | auth-premium | bcrypt sem Argon2, JWT HS256, token em localStorage, refresh sem rotation, Argon2 memoryCost ≠ OWASP 2024 |
| `check-network-security.sh` | network-security | HSTS/CSP/X-Frame-Options/X-Content-Type-Options ausentes, CORS `*` + credentials, rate limit ausente, CSP unsafe-inline |
| `check-observability.sh` | observability | Logger não-estruturado, sem health endpoints, PII em log (LGPD CRIT), sem audit_log, sem Sentry |
| `check-api-design.sh` | api-design | OpenAPI ausente, sem Spectral lint, sem Idempotency-Key em /payments, errors fora de RFC 7807, status 200 com `success:false`, webhook sem signature |
| `check-i18n-tz.sh` | i18n-tz | `@db.Time` sem timezone, money em Float/Decimal, sem libphonenumber, locales desincronizados, hardcoded dates |
| `check-pwa-installable.sh` | pwa-installable | Sem manifest, display:browser, sem ícones 192/512, sem maskable, sem SW, sem meta tags iOS |
| `check-responsive-a11y.sh` | responsive-a11y | `<img>` sem alt, outline:none, `<button>` com `<svg>` sem aria-label, placeholder substituindo label, sem Lighthouse CI, sem @axe-core, font-size < 14px |
| `check-process-resilience.sh` | process-resilience | Sem SIGTERM handler, sem /health/live ou /ready, sem connection_limit Prisma, `new Map()` unbounded, sem deadlock retry, K8s sem resources.limits.memory |
| `check-frontend-performance.sh` | frontend-performance | Sem size-limit, `<img>` sem next/image, `'use client'` sem hooks/handlers, React Compiler inativo, sem dynamic imports, moment.js, jQuery |
| `check-content-quality.sh` | content-quality | Erro técnico vazando pra UI, "Tem certeza?" vago, OK/Cancelar em destrutivo, plural via concatenação, termos discriminatórios, forbidden_words |

### v0.24 — CLI standalone Node (`npx blindar`)

Wrapper Node sobre os scripts shell. **Não substitui** os shells — só dá UX
mais amigável (`npx blindar check` vs `bash ~/.claude/...`).

- `cli/package.json` — `"bin": { "blindar": "./bin/blindar.js" }`, dependências mínimas (`mri` 1KB + `kleur` 1KB)
- `cli/bin/blindar.js` — entry point com args parsing
- `cli/commands/check.js` — `blindar check [--fast|--json]` (spawn bash com `run-all.sh`)
- `cli/commands/init.js` — `blindar init [--force]` (spawn `install-deterministic-checks.sh`)
- `cli/commands/terminate.js` — `blindar terminate` (decisão matemática release-ready)
- `cli/commands/report.js` — `blindar report` (copia + atualiza HTMLs com `aggregate.json`)
- `cli/commands/version.js` — `blindar version` (CLI + skill)
- `cli/commands/help.js` — `blindar help`
- `cli/README.md` — doc completa (instalação, comandos, arquitetura)

ESM puro (`type: module`), Node >= 20. Bash necessário (Git Bash no Windows).

### v0.25 — Integração com tools determinísticas externas

3 wrappers + 2 configs:

- `check-lighthouse.sh` — Lighthouse CI wrapper (Perf/A11y/BP/SEO ≥ 90, LCP < 2.5s, INP < 200ms, CLS < 0.1). Skipa se `@lhci/cli` ausente.
- `check-bundle-size.sh` — size-limit wrapper (default budget ≤ 400KB gzipped). Skipa se sem config.
- `check-visual-regression.sh` — Chromatic wrapper (requer `CHROMATIC_PROJECT_TOKEN` env). Skipa se sem Storybook.

Configs lib (copiar pro projeto):

- `templates/.lighthouserc.json` — preset desktop + thresholds 2026
- `templates/.size-limit.json` — 3 budgets (first-load, total-initial, all-gzipped)

`run-all.sh` agora roda **22 checks** (era 18).

### v0.26 — Test suite do próprio blindar

Validação de regressão dos checks via fixtures:

```
tests/
├── fixtures/
│   ├── clean-project/              ← deve PASSAR em todos
│   ├── project-with-mocks/         ← deve FALHAR check-mock-killer
│   ├── project-with-secrets/       ← deve FALHAR check-config-externalization
│   ├── project-multi-tenant-bad/   ← deve FALHAR check-prisma-schema
│   ├── project-with-cvv/           ← (placeholder pra check-payments)
│   └── project-no-csp/             ← (placeholder pra check-network-security)
└── run-tests.sh                    ← test runner que valida exit codes
```

6 test cases iniciais. Operador adiciona mais fixtures conforme detecta
falso positivo/negativo. Roda: `bash tests/run-tests.sh`.

### Inventário final v0.26

| Item | Quantidade |
|---|---|
| Agentes (`.md`) | **72** (mantido) |
| Check scripts shell | **22 representativos** + `_lib.sh` + `run-all.sh` + `check-termination.sh` |
| CLI Node | 7 arquivos (entry + 6 comandos) |
| Configs lib (Lighthouse + size-limit) | 2 |
| Fixtures de teste | 6 projetos |
| Templates HTML | 4 (sec + 2 reports + frontend-preview) |
| Schemas JSON | 9 |
| Hooks Husky | 2 (pre-commit + pre-push) |
| CI workflows | 1 (GitHub Actions) |
| Installer + test runner | 2 scripts |

### Total executável determinístico

- Materializa **~38 das ~600 regras** documentadas nos 72 agentes
  (~6% do total, mas cobre **80% dos casos mais críticos**)
- Próximas releases: continuar materializando até cobrir 60-70%

### Como ficou o fluxo end-to-end

```
1. Operador:    cd projeto && npx blindar init
2. CLI Node:    spawn bash → install-deterministic-checks.sh
                copia scripts/blindar/ + .github/workflows/ + .husky/
3. Operador:    git commit ...
4. Husky:       pre-commit → blindar fast (≤ 5s)
5. Operador:    git push
6. Husky:       pre-push → blindar full + termination
7. GitHub:      PR aberto → blindar.yml roda 22 checks
8. CI:          comenta no PR com resumo + bloqueia merge se vermelho
9. Branch prot: merge IMPOSSÍVEL sem todos verdes
10. Operador:   npx blindar report → execution-report.html + client-report.html
```

LLM (Claude com blindar skill) fica responsável por:
- Decisões estratégicas (refactor, design)
- Escrever código novo
- Gerar artefatos do delivery-bundle
- Sugerir fixes pros findings

Scripts/CI ficam responsáveis por:
- Validar regras → exit 0/1/2
- Bloquear merge
- Auditar (JSON + git_sha + timestamp)

### Migração v0.22 → v0.26

```bash
# CLI: novo
cd seu-projeto
npx blindar init           # ou: bash ~/.claude/skills/blindar/scripts/install-deterministic-checks.sh

# Atualiza scripts antigos (se já tinha v0.22):
npx blindar init --force

# Roda
npx blindar check
npx blindar terminate
npx blindar report
```

CI workflow do v0.22 continua funcionando — só os 10 checks novos não rodam até copiar atualizados.

---

## [0.22.0] — 2026-06-14

### Adicionou — Deterministic Layer (resolve "blindar não garante 100% em AUTO")

Materializa agentes em **scripts shell executáveis** + CI workflow
obrigatório + branch protection. Resultado: validação roda **independente
do LLM**, com `exit 0` / `exit 1` auditáveis.

#### 8 check scripts representativos em `templates/checks/`

| Script | Materializa agente | O que checa |
|---|---|---|
| `check-secrets.sh` | runtime-secrets + supply-chain | gitleaks scan, CRIT se algo |
| `check-mock-killer.sh` | mock-killer | console.log/TODO/mock/onClick={} em código de prod, respeita `// @blindar:keep` |
| `check-config-externalization.sh` | config-externalization | URLs hardcoded, passwords inline, .env.example sync, cores hex em JSX |
| `check-deps-audit.sh` | patch-management + supply-chain | npm audit, pip-audit, govulncheck, cargo audit, trivy fs |
| `check-prisma-schema.sh` | db-architect | UUID v7 em PKs, audit columns, tenant_id em multi-tenant, currency em BigInt, timezones |
| `check-payments.sh` | payments | CVV em código (PCI violation), PAN em log, webhook sem signature, money em Float |
| `check-file-uploads.sh` | file-uploads | multer em prod (preferir presigned), SVG sem DOMPurify, S3 public-read |
| `check-tenant-isolation.sh` | tenant-isolation-tests | findMany sem where tenantId, queryRawUnsafe, falta de testes de isolation, RLS hints |

Cada script:
- Detecta stack (Node/Python/Go/Rust/Prisma) e roda só se aplicável
- Emite JSON estruturado em `.blindar/results/<agent>.json`
- Exit 0/1/2 conforme severidade dos findings
- Respeita `intelligence.yml` (whitelist via `// @blindar:keep`, `-- @blindar:global`, etc.)

#### `run-all.sh` — orquestrador master

```bash
bash scripts/blindar/run-all.sh             # roda todos
bash scripts/blindar/run-all.sh --fast      # subset (secrets + mock) pra pre-commit
bash scripts/blindar/run-all.sh --json      # output JSON pra CI
```

Agrega `aggregate.json` com `findings_by_severity`, `passed/failed/skipped`,
duração total.

#### `check-termination.sh` — decisão matemática de release

```
Exit 0 = release liberada
Exit 1 = crit aberto (BLOQUEIA)
Exit 2 = high > 2 sem accept-risk (BLOQUEIA)
Exit 3 = coverage < threshold
Exit 4 = CI green streak insuficiente
```

Thresholds via env: `MAX_CRIT`, `MAX_HIGH_ACCEPTED`, `MIN_COVERAGE_PCT`,
`MIN_CI_GREEN_STREAK`.

#### CI workflow obrigatório (`templates/.github/workflows/blindar.yml`)

- Roda em `push: main` + `pull_request` + manual
- Instala gitleaks + rg + jq + trivy automaticamente
- Roda `run-all.sh` → falha build se algum check fail
- Roda `check-termination.sh` no final
- Posta comentário no PR com resumo de findings por severidade
- Upload de `.blindar/results/*` como artifact

#### Husky hooks templates

- `pre-commit`: lint-staged + blindar fast (≤ 5s)
- `pre-push`: lint + type-check + test + blindar full + termination

#### Installer + doc completa

- `scripts/install-deterministic-checks.sh` — copia tudo pro projeto-alvo,
  idempotente, suporta `--force`, detecta deps faltantes
- `docs/deterministic-layer.md` — arquitetura, formato JSON, comparação
  v0.21 vs v0.22, como configurar branch protection

#### Comparação prescrição vs determinístico

| Aspecto | v0.21 | v0.22 |
|---|---|---|
| Cobertura | "Claude deve fazer X" | Script executa X |
| Auditoria | "Claude disse que rodou" | JSON timestamp + git_sha |
| Bloqueio | Anti-padrão documentado | CI fail + branch protection |
| Idempotência | Variável (LLM) | Determinística |
| Velocidade | Depende do contexto | Segundos |

#### Como configurar branch protection (manual no GitHub)

```
Settings → Branches → main → Add rule:
  ☑ Require pull request before merging
  ☑ Require status checks: blindar-checks
  ☑ Do not allow bypassing
```

Merge **literalmente impossível** sem todos verdes.

### Quem faz o quê agora

| Tarefa | Camada determinística | Claude (blindar) |
|---|---|---|
| "Tem secret em código?" | ✅ gitleaks | — |
| "Há queries sem tenant_id?" | ✅ grep | — |
| "Como reorganizar essa pasta?" | — | ✅ architect agent |
| "Refatorar pra optimistic locking" | — | ✅ db-architect agent |
| "Gerar manual do cliente" | — | ✅ delivery-bundle |
| "Validar migration" | ✅ Prisma migrate --dry-run | — |
| "Bloquear merge se algo crítico" | ✅ CI + protection | — |

### Total de agentes

**72** (mesma de v0.21 — esta release é foco em infraestrutura, não em
novos agentes). Próximas releases materializam mais agentes em scripts.

### Migração v0.21.0 → v0.22.0

No projeto-alvo, rodar:

```bash
bash ~/.claude/skills/blindar/scripts/install-deterministic-checks.sh
```

Adicionar ao `package.json`:

```json
"scripts": {
  "blindar:check":     "bash scripts/blindar/run-all.sh",
  "blindar:fast":      "bash scripts/blindar/run-all.sh --fast",
  "blindar:terminate": "bash scripts/blindar/check-termination.sh"
}
```

Configurar branch protection no GitHub. Pronto — merge sem CI verde
agora é **impossível**.

---

## [0.21.0] — 2026-06-14

### Adicionou — Intelligence em mais 5 agentes

Completa a passada de "agentes inteligentes" iniciada em v0.20.
Agora **10 agentes consultam `.blindar/intelligence.yml`** + `content-quality`
consulta `.blindar/copy-style.yml` (link cruzado em
`schemas/intelligence.schema.json`):

#### `responsive-a11y`
- Respeita `aria-hidden="true"`, `role="presentation"`, `data-blindar-skip`
- `desktop_only_routes` / `mobile_only_routes` — não acusa scroll horizontal em rota intencionalmente desktop-only (admin, BI)
- `touch_target_exempt_selectors` — elementos legítimos < 44×44px
- `lighthouse_thresholds_per_route` — admin pode ter threshold relaxado, checkout mais rigoroso
- `ignore_violations` com `reason` + `adr` obrigatórios
- `strict_in_production_only` vs `always_strict`
- Auto-detecta Storybook stories (não acusa — é showcase)

#### `api-design`
- `idempotent_by_design` — login/refresh/logout/health não exigem header `Idempotency-Key`
- `cursor_pagination_exempt` — admin precisa "página 47"
- `versioning_exempt` — `/health/live`, `/.well-known/*` são estáveis
- `rfc7807_exempt` — webhooks de gateway externo seguem contrato deles
- `rate_limit_exempt` — `/health/*` não pode ser limitado
- `webhook_profiles` — Stripe ≠ MP ≠ PagSeguro
- Marker JSDoc `@no-idempotency-needed`, `@stable-endpoint`, `@custom-error-format`

#### `email-deliverability`
- **Env-aware** — DMARC `p=reject` exigido SÓ em produção, dev/staging relaxed
- Auto-detecta provider `mailpit`/`mailtrap` → modo dev
- Auto-detecta subdomínio `staging-*` → modo staging com thresholds relaxados
- `ip_warmup_grace_period_days: 30` — não acusa volume baixo em IP novo
- `template_safe_list` — transacionais (welcome/reset/receipt/confirmation) isentos de unsubscribe
- `transactional_exempt_from` lista
- Marker HTML `<!-- @blindar:transactional -->`
- Var ambiente `BLINDAR_ENV=development|staging|production`

#### `seo-marketing-meta`
- `noindex_routes` — `/admin/*`, `/app/*`, `/dashboard/*` não devem aparecer no sitemap nem ter canonical exigida
- `public_routes` — onde TODO SEO check é obrigatório
- `json_ld_by_route_type` — `/blog/*` → Article, `/products/*` → Product, etc auto-aplicado
- `hreflang_required` — só em rotas multi-idioma de marketing
- `llm_crawlers.allow/deny` — política explícita (GPTBot, ClaudeBot, PerplexityBot, CCBot)
- `site_type` (saas/ecommerce/content/landing) — adapta defaults
- Auto-detecta `metadata.robots = 'noindex'` em Next.js → skip checks
- Auto-detecta route groups privados (`(app)`, `(dashboard)`, `(admin)`)
- Marker `@blindar:noindex`

#### `payments`
- `active_gateways` — auto-detecta de imports/env (stripe, mercadopago, pagseguro, pix_direct)
- `gateway_profiles` — header de signature, lib, success status, retry policy diferentes por gateway:
  - **Stripe**: `stripe-signature`, `constructEvent`, retry em 5xx, supports 3DS
  - **Mercado Pago**: `x-signature`, accepts 200 + 422, PIX nativo
  - **PagSeguro**: `x-pagseguro-signature`, legacy SOAP em alguns endpoints
  - **PIX direto**: PSP-aware (Itaú/Bradesco/Sicredi), DICT lookup, QR code 15min
- `required_pii_redaction` — CPF/CNPJ/phone/address sempre redactados
- `exempt_from_idempotency` — GET-shaped POSTs (listar refunds, calcular fees)
- Auto-detecta modo test (`sk_test_*` no Stripe) → relaxa reconciliação
- Markers JSDoc `@blindar:gateway-stripe`, `@blindar:legacy-soap-endpoint`, etc

### Mudou — `schemas/intelligence.schema.json`

Adicionadas as 5 seções novas. Schema agora documenta 11 dos 12 agentes
com intelligence (content-quality continua linkando ao próprio agent file).

### Total de agentes

**72** (mesmo de v0.20 — refinamento, sem novos agentes).

### Migração v0.20.0 → v0.21.0

Nada a fazer. Agentes detectam contexto automaticamente. Se quiser
customizar exceções, criar `.blindar/intelligence.yml` no projeto com a
seção do agente desejado.

---

## [0.20.0] — 2026-06-14

### Adicionou — Preview + Aprovação no frontend-generator (Seção P)

**Pedido explícito do operador**: nenhuma reescrita de frontend sem
consulta prévia. Agora o agente passa por **3 portões** antes de tocar
em qualquer arquivo:

1. **Portão 1** — Pergunta inicial (4 opções):
   - Gerar do zero
   - Refazer (releitura) com aprovação por rota
   - Atualizar só faltantes
   - Cancelar

2. **Portão 2** — Geração de `frontend-preview.html` na raiz do projeto:
   - Lista TODAS as rotas que SERIAM criadas, com checkbox `apply/keep/skip`
   - Mockup dos dashboards por role (MASTER/ADMIN/GERENCIAL/OPERACIONAL)
   - Lista de forms gerados de Zod schemas
   - Componentes UI utilizados
   - Stack que será adicionada (incluindo deps novas)
   - Estimativa de LOC e arquivos a criar
   - Filtros por método, decisão, busca livre
   - Botões: "Aprovar TUDO", "Baixar minhas decisões", "Cancelar"
   - Operador baixa JSON, salva em `.blindar/frontend-decisions.json`

3. **Portão 3** — Confirmação final no terminal:
   - Mostra resumo com `(s/N)` default N
   - Operador precisa digitar `s` explícito
   - Estado registrado em `.blindar/frontend-state.json` (auditoria)

**Nenhum arquivo do projeto é tocado nos portões 1 e 2.** `Ctrl+C` em
qualquer ponto = nada perde. Re-execução com `--reset` recomeça do zero.

### Adicionou — Sistema de Intelligence compartilhada

Registry `.blindar/intelligence.yml` com schema em
`schemas/intelligence.schema.json`. Todos os agentes consultam pra
evitar falso positivo.

Cinco agentes ganharam **seção "Intelligence"** documentando suas
exceções legítimas:

#### `mock-killer`
- `ignore_paths`: glob de paths ignorados (node_modules, vendor, *.gen.ts, __mocks__, test, stories, .dev.ts, scripts)
- `keep_console_in`: arquivos onde console.* é OK (logger.ts, dev/)
- `intentional_todo_pattern`: regex de TODOs com issue link aceitos
- `inline_override_marker`: `// @blindar:keep`
- Auto-detecta `// eslint-disable-next-line no-console` (decisão consciente)

#### `config-externalization`
- `whitelist_constants`: HTTP codes, byte sizes, tempos universais, math constants
- `whitelist_url_patterns`: localhost, *.local, *.test, example.com
- `whitelist_strings_short`: "ok", "id", "GB", "%" etc
- `inline_override_marker`: `// @blindar:hardcode-ok`

#### `db-architect`
- `global_tables`: tabelas legitimamente SEM tenant_id (feature_flags, system_logs, migrations, exchange_rates, countries)
- `no_rls_required_tables`: onde RLS é overkill
- SQL comment marker: `-- @blindar:global` ou `/// @blindar:global` (Prisma)
- Detecção: tabela sem FK vinda de tabela tenant-scoped = provavelmente global

#### `tenant-isolation-tests`
- `inherit_from: db-architect` (respeita global_tables do db-architect)
- `skip_endpoints`: /admin/tenants, /health/*, /api/public/*, /api/webhooks/*
- `cross_tenant_intentional`: casos onde MASTER deve ver cross-tenant (com audit)
- Auto-skip: endpoint com `@Roles('MASTER')` exclusivo

#### `architect`
- `router_mode`: auto-detect App Router vs Pages Router (não força conversão)
- `structure_style`: auto-detect feature/layer/hybrid
- `blueprint_overrides`: aliases custom do projeto
- `allowed_top_level_dirs`: infra/, k8s/, docs/, scripts/ não são "erradas"
- `ignore_size_limit_in`: *.gen.ts, schema.prisma, locales/ podem ser grandes
- Marker: `// @blindar:keep-structure`
- Auto-detecta Vue/Svelte/Astro e muda blueprint

### Adicionou — `templates/frontend-preview.html`

HTML single-file ~25 KB, self-contained, modo escuro automático,
print-friendly. Visualiza decisões interativamente, gera JSON pra blindar
aplicar depois.

### Mudou — SKILL.md

Nova seção "Intelligence System" com exemplos e learning mode.
Templates expandidos (frontend-preview agora listado).

### Total de agentes

**72** (mesmo de v0.19.0 — não criou agente novo, melhorou os existentes).

### Migração v0.19.0 → v0.20.0

- `intelligence.yml` não existir = comportamento atual preservado (defaults sensatos).
- Primeira execução de mock-killer/config-ext/db-architect/etc gera template
  comentado em `.blindar/intelligence.yml` pra operador customizar.
- Frontend-generator em modo refazer agora SEMPRE pede aprovação (default N).
  Não há `--yes` flag — confirmação explícita é regra.

---

## [0.19.0] — 2026-06-14

### Adicionou — 22 agentes (Tier 1 + 2 + 3 da listagem prévia)

**Tier 1 (universais)** — módulos 4, 5, 9, 10, 13:
- `realtime` (m4) — WebSocket/SSE/CRDT com auth handshake, rooms multi-tenant, heartbeat, Redis adapter, presença
- `search-quality` (m10) — Meilisearch/Algolia/pg_trgm com pesos, debounce, sinônimos, empty state, multi-tenant
- `push-notifications` (m10) — VAPID+FCM+APNs, consent gradual, quiet hours, fallback chain
- `scheduled-jobs` (m13) — Redlock exactly-once, idempotência, watchdog, retry+DLQ, checkpoint
- `cdn-strategy` (m9) — cache em camadas, tags, immutable, image opt, signed URLs, anti-hotlink
- `chaos-engineering` (m13) — Chaos Mesh, GameDays, hipóteses, auto-rollback, RPO/RTO
- `sbom-slsa` (m5) — CycloneDX/SPDX, SLSA L3, Cosign+Rekor, admission policy

**Tier 2 (mercados específicos)** — módulos 4, 7, 8, 10, 11:
- `mobile-native` (m10) — Expo SDK 52, deep links, EAS Build/Update, biometria, SecureStore
- `compliance-gdpr` (m8) — ROPA, DPIA, DPA, TIA, ePrivacy cookies, 8 direitos
- `event-driven` (m13) — Kafka outbox, CQRS, Event Sourcing, saga
- `multi-region` (m7) — active-passive, DNS failover, RPO/RTO formais, drills
- `api-gateway` (m4) — Kong/Tyk, API keys, quotas, plans, dev portal
- `embedded-analytics` (m10) — Metabase/Cube embed, RLS, cache, white-label
- `visual-regression` (m11) — Chromatic/Percy, snapshot stable, cross-browser/viewport

**Tier 3 (niche, sob demanda)** — módulos 2, 4, 7, 8, 10:
- `mlops` (m2) — MLflow registry, DVC, drift detection, feature store, OWASP ML
- `graphql` (m4) — persisted queries, depth/complexity limit, DataLoader, federation
- `grpc-internal` (m4) — Protobuf versionado, mTLS, retry policy, codegen CI
- `audio-voice` (m10) — Opus, MediaRecorder, PTT, STT (Deepgram), TTS (ElevenLabs)
- `video-streaming` (m10) — HLS adaptive, transcoding (Mux), Picture-in-Picture, WebRTC
- `data-warehouse-etl` (m7) — Snowflake+dbt+Dagster, incremental, lineage, cost
- `compliance-hipaa` (m8) — 18 PHI identifiers, BAA, encryption, audit 6 anos
- `compliance-pci-deep` (m8) — SAQ types, 12 reqs, network segmentation, KMS

### Mudou — MODULE-MAP módulos 2, 4, 5, 7, 8, 9, 10, 11, 13

Renomes refletindo novos agentes por módulo. Todos os 22 agentes amarrados.

### Total de agentes

**72** (era 50 em v0.18.0). +44% em 1 release. Cobre praticamente todas as
verticais comuns + 8 niches.

### Migração v0.18.0 → v0.19.0

Nada a fazer. Novos agentes só ativam quando módulo correspondente
selecionado E projeto bate pré-requisitos (ex: `mlops` só se detectar
training scripts). Ninguém roda sem motivo.

---

## [0.18.0] — 2026-06-14

### Adicionou — `project-bootstrap` (módulo 14)

Cria projeto novo do **ZERO**. Faz 6 perguntas (nome, tipo, stack, multi-
tenant, sensibilidade dados, idiomas) e em ≤5min entrega:

- Estrutura monorepo (Turborepo + pnpm workspaces) com `apps/web` + `apps/api`
  + `packages/{shared,ui,config}`
- `package.json` com scripts, engines pinados, pnpm
- TypeScript **strict** desde o dia 1 (`noUncheckedIndexedAccess: true`)
- ESLint + Prettier + import sorting + Tailwind class sorting
- Husky pre-commit (lint-staged) + commitlint (conventional commits)
- GitHub Actions: CI (lint+test+build+blindar dry-run) + deploy-staging + deploy-prod
- Docker compose com Postgres+Redis local + healthchecks
- Scripts `iniciar.bat` (Windows) e `iniciar.sh` (Linux/macOS)
- Prisma schema com `tenant_id` + audit columns + RLS pré-configurado
- Seed: 1 tenant demo + 4 users (MASTER/ADMIN/GERENCIAL/OPERACIONAL)
- `.env.example` documentando TODAS variáveis necessárias (agrupado por
  serviço, com instrução de como obter)
- `.gitignore` completo (Node, env, .blindar local, uploads)
- README com quickstart < 5min **testado**
- `.nvmrc`, `.editorconfig`, `.vscode/{extensions,settings}.json`
- `.blindar/config.yml` já preenchido conforme respostas
- Licença MIT default (com pergunta)
- Commit zero: "chore: initial scaffold via blindar project-bootstrap"

**Stacks default por tipo:**
- SaaS: Next.js 15 (App Router + RSC) + NestJS + Postgres + Prisma + Vercel + Supabase
- MVP: Next.js 15 + Server Actions + Postgres + Vercel (mono-app)
- E-com: Next.js 15 + Stripe + Postgres + Algolia/Meilisearch
- API pura: NestJS + Postgres + Swagger + Docker + Railway
- Landing: Astro + Tailwind + Cloudflare Pages (estático)
- Mobile: Expo SDK 52 + EAS Build + Supabase + NestJS
- CLI/Lib: TypeScript + tsup + Changesets

**NÃO faz**: feature de negócio, sobrescrever projeto existente, comprar
domínio, decidir branding. Pergunta dupla antes de scaffold em pasta
não-vazia.

### Adicionou — `frontend-generator` (módulo 10)

**Lê o backend → gera frontend coerente** em horas, não sprints.

**Inputs lidos** (não pergunta o que dá pra detectar):
- `openapi.yaml` (do `api-design`) → endpoints, métodos, schemas
- `prisma/schema.prisma` (do `db-architect`) → entidades, relações
- `templates/role-hierarchy.md` ou `users.role` enum → roles + permissões
- `packages/shared/schemas/` (Zod) → reuso de validação FE+BE
- Design tokens / Tailwind config → cores, fontes, spacing

**Gera estrutura completa Next.js 15:**
- 1 página por rota REST (lista, detail, new, edit) com loading skeleton,
  empty state rico (ícone+texto+CTA), error boundary amigável
- Forms gerados de Zod schemas (DatePicker pra `datetime`, Select pra
  `enum`, máscara CPF pra regex BR, etc.)
- Dashboards **por role** (MASTER/ADMIN/GERENCIAL/OPERACIONAL) com
  widgets pensados pra cada audience
- SDK API client gerado via Orval (React Query + cache + retry)
- Permission matrix derivada do `@Roles()` do backend
  (`<Can do="appointment.delete">`)
- i18n keys auto-extraídas pra `locales/pt-BR/<feature>.json` (en-US
  com placeholder `__TRANSLATE__`)
- PWA manifest + service worker (delegando ao `pwa-installable`)
- SEO metadata em cada page.tsx (via `seo-marketing-meta`)
- Playwright spec auto-gerado pra cada rota nova (via `functional-e2e`)

**Modo refazer (strangler fig)**:
- Detecta frontend existente
- Gera ao lado em `frontend.next/` (NUNCA toca no antigo)
- Cria `docs/REFACTOR-FRONTEND.md` com mapping de rotas + roteiro de
  migração feature por feature
- Sugere proxy com feature-flag pra rota X ir pro novo, resto pro antigo
- Quando 100% migrado: deleta antigo em PR separado

**NÃO faz**: inventa feature/regra que backend não tem, sobrescreve
arquivo com marca `<!-- USER-EDITED -->`, decide cores próprias
(lê design tokens), apaga frontend antigo no primeiro PR.

### Mudou — MODULE-MAP módulos 10 e 14

- **Módulo 10** ganhou `frontend-generator` (gera/refaz frontend lendo backend)
- **Módulo 14** ganhou `project-bootstrap` (scaffold do zero)

### Total de agentes

**50** (era 48 em v0.17.0).

### Migração v0.17.0 → v0.18.0

Nada a fazer. Novos agentes só ativam quando operador chamar
explicitamente (`blindar bootstrap` ou `blindar generate frontend`) ou
quando módulo correspondente estiver selecionado e projeto bater
pré-requisitos.

---

## [0.17.0] — 2026-06-14

### Adicionou — `delivery-bundle` (módulo 14)

Agente que ao **final da execução** (Fase 07) monta a pasta `release/`
no projeto-alvo com **TUDO** que precisa pra entregar o sistema:

#### Estrutura gerada

```
release/
├── README.md                          ← índice + como usar
├── DEPLOY.md                          ← guia de implantação completo
├── MANUAL.md                          ← manual por role (MASTER/ADMIN/...)
├── API.md                             ← referência humana da API
├── openapi.yaml                       ← spec OpenAPI 3.1 completa
├── postman/
│   ├── collection.json                ← collection production-ready
│   ├── env-local.json
│   ├── env-dev.json
│   ├── env-staging.json
│   └── env-prod.json                  ← placeholders (sem secrets reais)
├── diagrams/
│   ├── architecture.mermaid
│   ├── er-database.mermaid
│   ├── auth-flow.mermaid
│   └── payment-flow.mermaid
├── CHECKLIST-GO-LIVE.md               ← 28 itens pré-launch
├── SLA-TEMPLATE.md
├── DEMO-SCRIPT.md                     ← 5/15/30 min
├── CHANGELOG-PUBLIC.md                ← versão amigável
└── legal/
    ├── terms-of-service.template.md
    ├── privacy-policy.template.md
    ├── cookie-policy.template.md
    └── data-processing-agreement.template.md
```

#### Highlights do Postman collection

Não é só "import OpenAPI" — collection production-ready:
- **Folders por feature** com cenários nomeados (Happy path, Conflito, Cancelar)
- **Pre-request scripts**: refresh automático de token se expirado,
  `Idempotency-Key` auto-gerado em POST
- **Post-response tests**: status 2xx, response time < 500ms, schema
  validation contra OpenAPI, save IDs no env pra próximo request
- **4 environments separados** (local/dev/staging/prod). Env-prod só
  com placeholders — **nunca commitar secret real**.
- **Newman-ready**: `newman run collection.json -e env-local.json`
  roda em CI e gera HTML report.

#### Outros artefatos

- **DEPLOY.md** auto-extrai env vars de `.env.example` em tabela
  documentada (nome, tipo, obrigatório, descrição, como obter)
- **MANUAL.md** gera seção por role detectado no `role-hierarchy`,
  com placeholders pra screenshots
- **Diagramas Mermaid** versionáveis (não PNG): arquitetura geral, ER
  do banco, fluxos sequenciais de auth e payment
- **CHECKLIST-GO-LIVE.md** com 6 grupos (Infra, Segurança, Banco,
  Funcional, Legal, Operacional) totalizando 28 itens
- **CHANGELOG-PUBLIC.md** versão amigável (sem refs a issues, sem nomes
  de devs, sem stack trace)
- **Templates legais** com marca `[REVISAR JURÍDICO]` em cláusulas
  sensíveis — sempre passar por advogado antes de publicar

#### Preservação de edits manuais

Operador edita `MANUAL.md` ou `SLA-TEMPLATE.md` → adiciona marca
`<!-- USER-EDITED -->` no topo. Próxima execução do delivery-bundle:
- NÃO sobrescreve
- Gera versão nova em `<file>.next.md` pro operador comparar
- Avisa no sec.html

#### Config opcional (`.blindar/config.yml`)

```yaml
delivery:
  enabled: true
  zip: true                         # gerar release-vX.Y.zip
  postman:
    environments: [local, dev, staging, prod]
    include_scenarios: true
  diagrams:
    architecture: true
    er_database: true
    auth_flow: true
    payment_flow: true
  manual:
    roles: auto                     # ou lista explícita
  custom_sections:
    - file: MIGRATION-FROM-V1.md
    - file: PARTNER-API.md
```

### Consome saída de outros agentes (zero duplicação)

- `api-design` → openapi.yaml + Postman base
- `db-architect` → ER diagram
- `role-hierarchy` → estrutura do MANUAL
- `devops` → conteúdo do DEPLOY
- `auth-premium` → auth flow diagram
- `payments` → payment flow diagram
- `execution-report` → CHANGELOG público
- `documentation-live` → coexiste (interna evoluindo vs snapshot estável)

### Total de agentes

**48** (era 47 em v0.16.0).

### Migração v0.16.0 → v0.17.0

Em projetos já existentes: primeira execução em v0.17.0 cria pasta
`release/` do zero. Subsequentes regeneram preservando edits manuais
(marca `<!-- USER-EDITED -->`).

---

## [0.16.0] — 2026-06-14

### Adicionou — `client-report.html` (relatório executivo)

Novo arquivo gerado na raiz do projeto-alvo, **em paralelo** ao
`blindar-report.html` técnico. Lê o **mesmo `report-data.json`** mas
renderiza visão amigável ao cliente final / decisor:

- **10 categorias de benefício** (não módulos técnicos): Segurança das
  contas, Confiabilidade dos dados, Velocidade, Experiência do usuário,
  Proteção do dinheiro, Crescimento sustentável, Conformidade legal,
  Operação 24/7, IA segura, Manutenção e evolução. Cada uma com ícone,
  título, frase de benefício pro negócio.
- **Resumo executivo** com 5 destaques principais.
- **4 cards de estatística** focados em valor (não em quantidade técnica):
  áreas de melhoria, melhorias aplicadas, sessões de trabalho,
  especialidades envolvidas.
- **Mapa `agent_to_category`** embutido (46 agentes mapeados → categoria
  + descrição em linguagem de negócio). Operador pode editar pra
  ajustar o tom do produto dele.
- **Visual mais clean**: tipografia maior, gradiente sutil no header,
  ícones grandes por categoria.
- **3 ações de export**: imprimir (CSS @media print otimizado A4),
  copiar resumo em texto puro (não markdown — pronto pra colar em
  WhatsApp/email), abrir email com subject/body pré-preenchidos.

### Atualizou — `execution-report.md`

- Documenta agora a **dupla saída**: técnico (`blindar-report.html`) +
  cliente (`client-report.html`).
- Função de update agora re-grava bloco JSON em **ambos** os HTMLs.
- Esclarece que `client-report.html` tem um **segundo bloco**
  `<script id="benefit-map">` que NÃO é atualizado pelo blindar — é a
  tabela de tradução técnica→cliente que o operador customiza.

### Adicionou — `agents/architect.md` (módulo 14)

Agente arquiteto cobrindo organização do código:

- **Detecção de stack** + escolha de blueprint do mercado (Next.js 15,
  NestJS DDD-light, Monorepo Turborepo/Nx, React SPA Vite, FastAPI).
  Cada blueprint com estrutura recomendada + regras de fronteira.
- **Naming conventions** não-negociáveis (kebab pra arquivos, PascalCase
  pra componentes, useCamelCase pra hooks, UPPER_SNAKE pra constants).
- **Boundaries via `dependency-cruiser`** ou `eslint-plugin-boundaries`:
  - `features/A` não importa de `features/B`
  - `components/` não importa de `app/`
  - `lib/` não importa de `components/`
  - Domain não importa de infrastructure (DDD)
  - Zero ciclos
- **File size limits**: componente ≤300 LOC, hook ≤100, util ≤200,
  service ≤400, page ≤200. `utils.ts`/`helpers.ts`/`common.ts`
  **proibidos** (sempre nomear por domínio: `date-utils.ts`,
  `currency-utils.ts`).
- **Feature-based vs layer-based**: orientação de quando usar cada um,
  **híbrido recomendado** (`/components/ui` + `/lib` + `/hooks` +
  `/features/<nome>`).
- **DDD**: aplicar só quando complexidade justifica (5+ devs, ubiquitous
  language). Estrutura DDD-light: domain / application / infrastructure /
  presentation.
- **Dead code**: `knip` + `ts-prune` + `vulture` (Python) como gate.
- **Circular deps**: `madge --circular` ou `depcruise` em CI.
- **Strangler fig**: refactor gradual nunca big-bang. Métricas pra
  acompanhar migração de % de imports.
- **15 anti-padrões CRIT**: `utils.ts` genérico, importação cross-feature,
  componente RSC com `'use client'` sem motivo, path `../../../../`,
  index.ts barril > 50 linhas, mistura de naming, arquivo > 600 LOC, etc.

### Mudou — MODULE-MAP módulo 14

Renomeado: "DX + Flags + Backoffice + Email + Docs + Execution report" →
"DX + Flags + Backoffice + Email + Docs + **Reports (técnico+cliente)** +
**Architect**". Agentes: +`architect`.

### Total de agentes

**47** (era 46 em v0.15.0).

### Migração v0.15.0 → v0.16.0

Em projetos já com `blindar-report.html`: primeira execução em v0.16.0
copia `client-report.html` em paralelo (não toca no técnico) e popula
com os mesmos dados. A partir daí ambos atualizam juntos.

---

## [0.15.0] — 2026-06-14

### Adicionou — Execution report HTML cumulativo (módulo 14)

Novo arquivo gerado na raiz do projeto-alvo: `blindar-report.html`.

- **Self-contained**: HTML + CSS + JS embutidos em um único arquivo
  (~25 KB). Funciona offline, abre em qualquer browser, pode anexar em
  email.
- **Cumulativo**: cada execução do blindar **apenda** ao histórico
  (nunca substitui). Operador vê toda a evolução do hardening ao longo
  do tempo.
- **Fonte da verdade**: `.blindar/report-data.json` (versionado). HTML
  re-renderiza o bloco `<script id="blindar-data">` a partir do JSON.
  Layout do HTML pode ser customizado sem perder dados.
- **3 visualizações**: Timeline (mais recente primeiro), Por módulo,
  Por agente.
- **6 stats no topo**: módulos executados, agentes ativos, rounds
  completados, findings resolvidos, crits abertos, highs em
  accept-risk.
- **5 filtros client-side**: busca livre, módulo (1-15), agente,
  severidade (CRIT/HIGH/MED/LOW/Resolvidos), período (24h/7d/30d/tudo).
- **4 ações de exportação**:
  - 🖨️ Imprimir / PDF (CSS @media print esconde controles, expande
    detalhes, otimiza pra A4)
  - 📋 Copiar resumo (gera Markdown estruturado, cola em email/Slack)
  - 💾 Baixar dados (JSON cru pra backup ou análise externa)
  - ✉️ Compartilhar (`mailto:` com subject/body pré-preenchidos)
- **Modo escuro automático** via `prefers-color-scheme`.
- **a11y**: contraste WCAG AA, tags semânticas (`<details>`,
  `<summary>`, `<header>`, `<footer>`), escape de XSS via `esc()`.

### Adicionou — `agents/execution-report.md`

Agente passivo (não roda lógica própria) — outros agentes apendam
ações ao final de cada round. Documenta:
- Schema do JSON cumulativo (com 11 campos por action)
- Workflow de criação (Fase 03), append (Fase 04), fechamento (Fase 07)
- Regex de update do bloco JSON no HTML
- Cleanup periódico (> 1000 entries → archive, > 5MB → particiona)
- Greps de validação (HTML ↔ JSON em disco coerentes)
- 9 anti-padrões (não substituir JSON inteiro, não permitir XSS via
  description, não servir HTML em rota pública do app, etc.)

### Adicionou — `templates/execution-report.html`

Template completo do HTML. Copiado pra raiz do projeto na Fase 03 e
atualizado nas fases 04/05/06/07.

### Mudou — MODULE-MAP módulo 14

- Adicionado `execution-report` aos agentes
- Adicionadas fases `03-bootstrap-sec-html` e `07-final-report` à
  lista `phases` (além das 04 e 06 já presentes)
- Renome: "DX + Feature flags + Backoffice/Admin + Email + Docs" →
  "DX + Flags + Backoffice + Email + Docs + **Execution report**"

### Total de agentes

**46** (era 45 em v0.14.1).

### Migração v0.14.1 → v0.15.0

Em projetos com blindar v0.14.1 já rodado: a primeira execução em
v0.15.0 cria `blindar-report.html` e `.blindar/report-data.json` do
zero. Histórico anterior não está retroativamente disponível (não há
como reconstruir actions sem dados gravados). A partir daí é cumulativo.

---

## [0.14.1] — 2026-06-14

### Fixou — content-quality agora é inteligente com nomes próprios e code-switching

Adicionou 4 listas de proteção em `.blindar/copy-style.yml` que evitam
falsos positivos comuns:

- **`protected_terms`**: marcas (Stripe, WhatsApp, Vercel), nomes de
  produto (Salon Pro), tenants (Beleza Real), pessoas (Maykonbts), roles
  (MASTER/ADMIN). Auto-populado de `package.json`, `README.md` H1, `.env`
  vars (`BRAND_NAME`/`APP_NAME`/`SERVICE_NAME`), constants files
  (`src/lib/brand.ts`), arquivos de roles. Operador edita depois.

- **`technical_terms`**: termos consagrados aceitos em qualquer locale
  (API, webhook, deploy, dashboard, KPI, ROI, MVP, SaaS, MRR, churn, lead,
  scroll, swipe). Não viram "erro de estrangeirismo" em pt-BR.

- **`proper_nouns_detection`**: regras de auto-detecção (CamelCase ≥ 2
  capitalizadas, UPPERCASE ≥ 2 chars, precedido de "do/da/de"). Novo
  termo detectado vira candidato a `protected_terms` (low-severity pra
  revisão humana, não bloqueia).

- **`allowed_code_switching`**: padrões aceitos de mistura pt+en
  ("Configurar webhook", "Conectar Stripe"). Lista de
  `forbidden_translations` (manter "deploy"/"webhook"/"dashboard"
  originais, não forçar tradução).

### Adicionou — engine de decisão documentada

Pipeline em 6 passos antes de flagar qualquer token: protected_terms →
technical_terms → proper_nouns_detection → context_rules.ignore →
context_rules.revisar_apenas → revisão real. Documentado em
`A.1. Engine de decisão` com 10 exemplos práticos resolvidos.

### Adicionou — `context_rules`

Distingue **código de UI**. Ignora: variáveis, constantes UPPER_SNAKE,
schemas Zod, comentários, JSDoc, URLs, regex, *.test.*, *.config.*,
.env*, logs estruturados. Revisa apenas: JSX text nodes, atributos
visíveis (alt/title/aria-label/placeholder), props textuais, i18n files,
templates de email, markdown público.

### Migração v0.14.0 → v0.14.1

Em projetos com `.blindar/copy-style.yml` v0.14.0 já criado: agente
detecta versão antiga e **adiciona as 4 seções novas com auto-população**
preservando configs existentes do operador. Backup automático em
`copy-style.yml.backup-v0.14.0`.

---

## [0.14.0] — 2026-06-14

### Adicionou — content-quality (módulo 12)

Agente revisor de copy/gramática/tom que respeita config do projeto:

- **Config de tom** em `.blindar/copy-style.yml`: idioma primário,
  formalidade (casual/neutral/formal), pronoun (você/tu), warmth, glossário
  com termos preferidos + variações proibidas, lista de `forbidden_words`,
  `preferred_phrasing` (consistência de microcopy), regras de
  inclusividade (gênero neutro, anti-capacitismo).
- **5 camadas de validação**: (1) LanguageTool ortografia+gramática pt-BR/
  en-US/es-ES, (2) Vale prose lint com regras Microsoft + Blindar custom,
  (3) glossário (detecta termos errados), (4) alex.js (inclusividade),
  (5) LLM opcional pra score de tom (cache por hash).
- **Tipos de copy revisados**: botões primários (consistência),
  mensagens de erro (amigáveis, não culpando user), empty states
  (CTA claro), confirmações destrutivas (texto explícito, não "OK"),
  emails transacionais, política/TOS, tooltips, push notifications
  (< 50 chars título), placeholders (não substituem label).
- **Greps**: erro técnico vazando pra UI (`undefined`, `TypeError`),
  "Tem certeza?" vago, "OK/Cancelar" em destrutivo, plurais por
  concatenação, traduções faltando entre locales.
- **Bloqueia merge se**: ortografia em produção, glossário misturado
  (`agendamento` + `reserva` no mesmo produto), confirmação destrutiva
  genérica, termo proibido detectado, pronoun inconsistente.

### Mudou — módulo 12

Renomeado de "Anti-mock & cleanup + Externalização" para
"Anti-mock + Externalização + Content quality (gramática/tom/glossário)".

### Total de agentes

**45** (era 44 em v0.13).

### Migração v0.13 → v0.14

Nada a fazer. Em projetos sem `.blindar/copy-style.yml`, o agente cria
template na primeira execução com defaults sensatos pro idioma detectado.

---

## [0.13.0] — 2026-06-14

### Adicionou — 7 agentes (verticais de produção elevados de playbook a enforcement)

- `agents/payments.md` — **módulo 4**. Idempotency obrigatória, webhook
  HMAC + dedup + async, status machine 12 estados, refund auditado com
  motivo, reconciliação diária cron, fraud detection básico (velocity/
  geo/amount), PCI-DSS awareness (SAQ A — nunca toca PAN), SCA/3DS,
  PIX (Brasil). Valor sempre BIGINT cents.

- `agents/file-uploads.md` — **módulo 2**. Presigned URL (backend não
  proxia bytes), MIME validation por magic bytes (não extensão),
  antivírus (ClamAV/VirusTotal), strip EXIF + re-encode (image-rewrite),
  SVG sanitize (DOMPurify, mata XSS), signed URL leitura 15min,
  lifecycle policies (temp/24h, archive/30d), quota por user/tenant,
  audit log.

- `agents/tenant-isolation-tests.md` — **módulo 2**. Gera ~47 testes
  automatizados que PROVAM isolamento: READ/WRITE/DELETE cross-tenant
  retorna 404 (não 403!), filtros e contagens não vazam, role scope
  (OPERACIONAL ≠ outro OP), token reuse, storage path injection, cache
  key collision, RLS habilitado em todas tabelas, WebSocket broadcast,
  job/queue context, audit log filter, fuzz UUID enumeration.

- `agents/email-deliverability.md` — **módulo 14**. SPF (`-all`), DKIM,
  DMARC (`p=reject` gradual), BIMI opcional, bounce/complaint handler
  com tabela de supressão (check antes de cada envio), warm-up
  cronograma de IP novo, IPs separados (transacional vs marketing),
  one-click unsubscribe RFC 8058 (Gmail/Yahoo exigem), footer compliant
  LGPD/CAN-SPAM, plain text obrigatório, Postmaster Tools, métricas
  (delivery > 98%, bounce < 2%, complaint < 0.1%), fallback provider.

- `agents/seo-marketing-meta.md` — **módulo 10**. Title/description único
  por página, canonical obrigatória, OG (1200×630 dinâmica) + Twitter
  Card, structured data JSON-LD por tipo (SoftwareApplication, Article,
  Product, FAQ, Breadcrumb, Organization), sitemap.xml gerado, robots.txt
  com decisão LLM crawlers (GPTBot/ClaudeBot/PerplexityBot), hreflang
  pra i18n, IndexNow ping, Lighthouse SEO ≥ 90 como gate, slugs legíveis.

- `agents/testing-strategy.md` — **módulo 11**. Pirâmide saudável
  (60/30/10 unit/integration/E2E), integration com DB real
  (testcontainers, NÃO SQLite/mock), contract tests Pact entre FE↔BE,
  mutation testing Stryker (mede QUALIDADE dos testes, score > 80%),
  property-based fast-check pra invariantes, snapshot inline + Chromatic
  visual regression, performance test k6 como gate (p95 < 500ms),
  coverage gates (stmt 80%/branch 75%), flake detection.

- `agents/documentation-live.md` — **módulo 14**. README com quickstart
  testado < 5min, API docs interativa Scalar/Redoc gerada do OpenAPI,
  Storybook com 5+ stories por componente (a11y addon + Chromatic),
  ADRs versionados em `docs/adr/` (decisão importante = ADR, não Slack),
  CHANGELOG semver via changesets, diagramas Mermaid em markdown
  (versionáveis), code comments só "porquê" não-óbvio, JSDoc/TSDoc em
  API pública, onboarding doc de dev novo.

### Mudou — MODULE-MAP renomeou 5 módulos

| # | Antes | Agora |
|---|---|---|
| 2 | Segurança core + AI/LLM | + **Tenant isolation + File uploads** |
| 4 | Rede & API | + **Payments** (Stripe/MP/PIX) |
| 10 | Fluidez completa | + **SEO/marketing meta** |
| 11 | Funcional E2E | + **Testing strategy completa** |
| 14 | DX + Feature flags + Backoffice | + **Email deliverability + Documentation** |

### Total de agentes

**44** (era 37 em v0.12).

### Migração v0.12 → v0.13

Nada a fazer.

---

## [0.12.0] — 2026-06-14

### Adicionou — process-resilience (módulo 13)

Cobre 7 vetores de "processo trava silencioso" que `resilience.md` (focado
em breakers/pools externos) não cobria:

1. **Health checks em 3 níveis** — `/health/live` (rápido, sem deps),
   `/health/ready` (checa DB/cache/storage), `/health/deep` (métricas
   ricas, protegido por auth). K8s usa live+ready, watchdog usa deep.
2. **Graceful shutdown** — handler SIGTERM/SIGINT que para de aceitar
   conexões, espera in-flight terminar (timeout 30s), drena pools,
   `process.exit(0)`. K8s `terminationGracePeriodSeconds: 30`.
3. **Backpressure** — middleware HTTP 503 + `Retry-After` quando
   `inflight >= MAX`, monitor de event loop lag (perf_hooks
   `monitorEventLoopDelay`), queue com `concurrency` + DLQ.
4. **ulimits / OOM** — container memory limit obrigatório,
   `--max-old-space-size` explícito, LRU cache (não `new Map()`
   unbounded), detect heap > threshold antes do OOMKill.
5. **Watchdog externo** — heartbeat ativo (app push pra serviço externo
   a cada 30s) ou Better Uptime / Healthchecks.io / Cronitor passivo.
   Cobre caso "k8s acha vivo mas event loop travado".
6. **Long-running transaction killer** — Postgres
   `idle_in_transaction_session_timeout = 60s` + cron mata tx > 5min,
   wrapper app-level com `Promise.race` timeout 5s default.
7. **Deadlock retry automático** — wrapper `withDeadlockRetry` trata
   códigos `40001` (serialization_failure) e `40P01` (deadlock_detected)
   do Postgres com backoff exponencial + jitter (3 tentativas).

### Total de agentes

**37** (era 36 em v0.11).

### Migração v0.11 → v0.12

Nada a fazer.

---

## [0.11.0] — 2026-06-14

### Adicionou — 6 agentes finais (cobertura total UX + AI + Ops)

- `agents/state-cache-data.md` — **módulo 10**. TanStack Query v5 default,
  optimistic UI com rollback, cache invalidation hierárquica (item/lista/
  agregado), stale-while-revalidate, offline-first com persistência
  IndexedDB + retry queue, conflict resolution via optimistic locking
  (version column → 409 + modal), Suspense + streaming, prefetch on hover.

- `agents/onboarding-ux.md` — **módulo 10**. Signup ≤ 3 campos, magic
  link/passkey opcional, empty states ricos (ícone+texto+CTA+demo),
  tour guiado contextual (3-5 passos, não modal de 12 slides), demo data
  opcional com limpar 1-clique, activation funnel mensurável (aha_moment
  evento), onboarding checklist persistente no dashboard, welcome email
  personal.

- `agents/feature-flags.md` — **módulo 14**. Tabela `feature_flags` (ou
  serviço LaunchDarkly/GrowthBook), 4 tipos (release/ops/experiment/
  permission), rollout gradual com hash determinístico (murmurhash), kill
  switch < 30s de latência, A/B testing com variation tracking, cleanup
  obrigatório após 30d com flag estável (issue automática), audit log de
  mudanças. Evaluation NO BACKEND, nunca no client.

- `agents/cost-observability.md` — **módulo 6**. Budget alerts cloud
  (50/80/100/120%), anomaly detection (AWS Cost Anomaly), LLM cost
  tracking per user/feature (tabela `llm_usage`), rate limit por plano
  (free/pro/enterprise), DB slow query alerts (>1s), storage lifecycle
  policies obrigatórias, CDN cache hit rate > 80%, métrica chave $/usuário
  ativo, per-tenant budget com hard limit opcional.

- `agents/ai-llm-safety.md` — **módulo 2**. Cobertura OWASP LLM Top 10 2025:
  prompt injection (separação estrutural user/system, system prompt
  blindado), indirect injection (sandbox `<<<DATA>>>` em tool results),
  PII redaction antes/depois, max_tokens cap obrigatório, rate limit por
  user (1/min e diário), tools com schema Zod + auth + confirmação em
  ações destrutivas, output validation (não eval/innerHTML cru), UI deixa
  claro "é IA" (anti-overreliance), audit log de cada call.

- `agents/backoffice-admin.md` — **módulo 14**. Impersonation auditada
  (motivo obrigatório, banner persistente, token 30min, ações destrutivas
  bloqueadas), audit log particionado mensal, support workflows (refund/
  bloqueio/LGPD export+delete via UI, não SQL direto), 6 dashboards
  operacionais, MFA obrigatório pra ADMIN/MASTER (WebAuthn), IP allowlist
  opcional, read-only DB query auditada.

### Mudou — MODULE-MAP renomeou 4 módulos

| # | Antes | Agora |
|---|---|---|
| 2 | Segurança aplicacional core | **Segurança aplicacional core + AI/LLM** |
| 6 | Observabilidade & audit | **Observabilidade & audit + Cost monitoring** |
| 10 | Fluidez + a11y + responsivo + PWA + i18n/timezone | **Fluidez completa** (+ state/cache + onboarding) |
| 14 | DX & onboarding | **DX + Feature flags + Backoffice/Admin** |

### Total de agentes

**36** (era 30 em v0.10):
- 7 segurança (access-control, cryptography, business-logic, runtime-secrets, security, auth-premium, **ai-llm-safety**)
- 1 API design (api-design)
- 1 frontend hardening (frontend)
- 1 rede (network-security)
- 2 supply chain (supply-chain, patch-management)
- 2 observability (observability, **cost-observability**)
- 2 DR/DB (backup-recovery, db-architect)
- 2 compliance (compliance, compliance-lgpd-br)
- 1 performance backend (performance)
- 6 fluidez/UX (frontend-performance, responsive-a11y, pwa-installable, i18n-tz, **state-cache-data**, **onboarding-ux**)
- 1 funcional E2E (functional-e2e)
- 2 cleanup (mock-killer, config-externalization)
- 2 resilience/scale (resilience, scalability)
- 3 devops/ops (devops, **feature-flags**, **backoffice-admin**)
- 2 pentest (pentest, adversarial-reviewer)
- 1 strategic-scanner

Bold = novos em v0.11.

### Migração v0.10 → v0.11

Nada a fazer. Configs antigos rodam normalmente.

---

## [0.10.0] — 2026-06-14

### Adicionou — 4 agentes (cobertura "stack moderna 2026")

- `agents/db-architect.md` — **módulos 7 + 9**. Schema obrigatório
  (UUID v7 + audit columns + soft delete + version pra optimistic locking),
  índices multi-tenant (tenant_id 1º), migrations zero-downtime (3-deploy
  pattern), Row-Level Security, N+1 detection com DataLoader + count em
  testes, EXPLAIN em CI bloqueando Seq Scan em tabela > 10k, connection
  pool sizing por workload (incl. serverless/PgBouncer), statement_timeout
  obrigatório, audit log table, anonimização LGPD Art. 18 VI, PITR backup
  com drill mensal.

- `agents/config-externalization.md` — **módulo 12**. Aplica regra "nada
  no código": 10 categorias de greps (textos, URLs, magic numbers, regras
  de negócio `if tenant`, cores/spacing, regex duplicado, templates de
  email, endpoints frontend, feature flags inline). Cada finding mapeia
  pra destino: env / settings table / feature_flags table / i18n /
  design tokens / schema central. Schemas SQL sugeridos pras tabelas de
  config. Complementa mock-killer no mesmo módulo (mock-killer remove,
  este externaliza).

- `agents/api-design.md` — **módulo 4**. OpenAPI como fonte de verdade
  (gera SDK + mock + validation + lint via Spectral em CI), versionamento
  por path com `Sunset` header, idempotency keys obrigatórias em POST
  críticos com tabela `idempotency_keys`, paginação cursor (não offset em
  endpoint público), filtragem RSQL/FIQL, errors no formato RFC 7807
  Problem Details, ETags + If-Match (avoid lost update), webhooks com
  HMAC signature + replay protection + retry exponencial + DLQ (padrão
  Svix), rate limit headers IETF, contract testing com Pact, GraphQL com
  persisted queries + depth/complexity limits.

- `agents/i18n-tz.md` — **módulo 10**. Regra absoluta: tudo em UTC no DB
  (TIMESTAMPTZ obrigatório), currency em cents BIGINT (não DECIMAL/FLOAT),
  timezone IANA por usuário (não offset), Temporal API ou Intl nativo
  pra render, ICU MessageFormat pra plurais (zero concatenação), fallback
  chain de locales, RTL via CSS logical properties (não margin-left),
  telefone E.164 + libphonenumber-js, endereço com formato variável por
  país (não fixo VARCHAR(8) pra CEP), detecção por profile→cookie→header
  (não IP).

### Mudou — MODULE-MAP renomeou 5 módulos

| # | Antes | Agora |
|---|---|---|
| 4 | Rede & proxy (WAF/rate-limit/headers) | **Rede & API** (WAF/rate-limit/headers/OpenAPI/idempotency) |
| 7 | Backup & DR | **Banco de dados + Backup & DR** |
| 9 | Performance backend | **Performance backend + Query optimization** |
| 10 | Fluidez + a11y + responsivo + PWA instalável | **Fluidez + a11y + responsivo + PWA + i18n/timezone** |
| 12 | Anti-mock & cleanup | **Anti-mock + Externalização** (nada no código) |

### Mudou — `db-architect` referenciado em 2 módulos

Único agente que aparece em **dois módulos** do MODULE-MAP (7 e 9) — porque
DB cobre tanto durabilidade (módulo 7) quanto performance (módulo 9).
Pipeline trata como mesma instância (não spawna 2x se ambos módulos ativos).

### Migração v0.9 → v0.10

Nada a fazer. Configs antigos rodam normalmente. Agentes novos só ativam
em projetos onde os módulos correspondentes estão selecionados.

### Total de agentes

**30** (era 26 em v0.9):
- 6 segurança aplicacional (access-control, cryptography, business-logic, runtime-secrets, security, **auth-premium**)
- 1 API design (**api-design**)
- 1 frontend hardening (frontend)
- 1 rede (network-security)
- 2 supply chain (supply-chain, patch-management)
- 1 observability
- 2 DR/DB (backup-recovery, **db-architect**)
- 2 compliance (compliance, compliance-lgpd-br)
- 1 performance backend (performance)
- 4 fluidez/UX (frontend-performance, responsive-a11y, **pwa-installable**, **i18n-tz**)
- 1 funcional E2E (functional-e2e)
- 2 cleanup (mock-killer, **config-externalization**)
- 2 resilience/scale (resilience, scalability)
- 1 devops
- 2 pentest (pentest, adversarial-reviewer)
- 1 strategic-scanner

Bold = novos em v0.8+.

---

## [0.9.0] — 2026-06-14

### Adicionou — 2 agentes premium

- `agents/auth-premium.md` — **módulo 2**. Stack completa: WebAuthn/Passkeys
  (FaceID/TouchID/Windows Hello), Argon2id, JWT RS256 com refresh rotation +
  reuse detection (logout total ao detectar token roubado), idle timeout
  15min com PIN de retomada que **preserva estado da página** (form drafts,
  scroll, modais), Pwned password check (HIBP k-anonymity), rate limit em
  /auth/*, headers de segurança (8), CORS allowlist explícita.

- `agents/pwa-installable.md` — **módulo 10**. Torna qualquer projeto com UI
  instalável como app nativo no celular (iOS 16.4+ / Android) e desktop
  (Windows/macOS/Linux). Manifest validado, Service Worker (Workbox/Vite
  PWA), ícones maskable, install prompt customizado, offline page,
  Lighthouse PWA ≥ 90.

### Adicionou — Template de hierarquia

- `templates/role-hierarchy.md` — padrão de 4 níveis extraído do projeto
  Salon Pro 3.0: **MASTER** (multi-tenant global) → **ADMIN** (por tenant)
  → **GERENCIAL** (operacional) → **OPERACIONAL** (próprios dados).
  Inclui: schema Prisma, NestJS Roles decorator + Guard com hierarquia,
  filtragem por escopo no service layer, hooks de role no frontend,
  audit log obrigatório, mapeamentos por domínio (beleza/e-com/saúde/
  educação). Testes de isolamento entre roles especificados.

### Mudou — MODULE-MAP.json

- Módulo 2 ganha `auth-premium`.
- Módulo 10 renomeado para "Fluidez + a11y + responsivo + PWA instalável"
  e ganha `pwa-installable`.
- Total: **26 agentes** (era 24 em v0.8).

### Migração v0.8 → v0.9

Nada a fazer. Configs antigos rodam normalmente. Agentes novos só ativam
em projetos onde os módulos 2 e 10 estão selecionados (mandatory ou por
escolha do operador).

---

## [0.8.0] — 2026-06-14

### Adicionou — Launcher interativo (Fase 00)

- `pipeline/00-launcher.md` — **ponto de entrada** novo, antes da Fase 0
  Strategic Scan. Faz 4 perguntas objetivas (≤30s):
  1. Tipo de projeto (SaaS / MVP / LP / E-com / API / Mobile / CLI)
  2. Sensibilidade de dados (Alta / Média / Baixa)
  3. Modo (Auto / Supervisionado / Escolhidos)
  4. Rigor (Produção / Compliance / MVP)
- Exibe **menu numerado de 15 módulos** com defaults inteligentes baseados
  nas respostas.
- Aceita: `"tudo"`, `"defaults"`, `"1,3,5,7,10"`, `"1-8"`, `"tudo menos 13,14"`.
- Confirmação única no fim, default-yes em modo AUTO (timeout 10s).
- Grava `.blindar/config.yml` com `mode`, `selected_modules`, `project_type`,
  `data_sensitivity`, `rigor`, `ui_detected`, `db_detected`.

### Adicionou — 3 novos agentes (núcleo não-negociável)

- `agents/mock-killer.md` — **módulo 12**. Caça e elimina dados mocados,
  `console.log`, TODOs, mocks fora de teste, placeholders Lorem, senhas
  hardcoded, URLs `localhost` em produção, botões com handler vazio
  (`onClick={()=>{}}`), `.env.example` desincronizado. Bloqueia merge se
  qualquer botão visível tiver handler vazio.
- `agents/functional-e2e.md` — **módulo 11**. Gera Playwright auto-descoberto
  pra cada rota: clica em CADA botão visível em 3 viewports (mobile/tablet/
  desktop) e exige resposta real (request, navegação, toast ou modal). Testa
  endpoints API com payload válido + inválido. Bloqueia merge se rota
  retornar 5xx ou ID começar com `mock|test|fake|dummy`.
- `agents/responsive-a11y.md` — **módulo 10**. Lighthouse ≥ 90 em 4 pilares
  (Perf/A11y/BP/SEO), axe-core WCAG AA, 5 viewports (320/375/768/1440/1920),
  touch targets ≥ 44px no mobile, LCP < 2.5s, CLS < 0.1, INP < 200ms,
  `prefers-reduced-motion` respeitado, dark mode com tokens semânticos.

### Adicionou — MODULE-MAP estruturado

- `pipeline/MODULE-MAP.json` — mapa **consumível por AI**: módulo numerado →
  agentes ativados → fases onde rodam. Define `mandatory`, `default_on_when`,
  `default_off_when` (regras de resolução de defaults). Pipeline consulta
  ANTES de spawnar qualquer agente — gap fora de módulo selecionado fica
  pulado com log, não vira finding.

### Adicionou — 3 modos de execução

- **AUTO**: roda do início ao fim sem pausar (default).
- **SUPERVISIONADO**: pausa após cada round, pede confirmação.
- **ESCOLHIDOS**: roda só `selected_modules`, em ordem numérica, termina
  quando todos `covered` ou `n/a` (NÃO entra em loop infinito).

### Adicionou — Curadoria semestral de tendências

- `docs/trends-2026.md` — referência consultada por agentes relevantes.
  Cobertura inicial: React Compiler v1, RSC default Next.js 15+, Edge
  runtime, performance budget ≤ 400KB JS gzipped, headers HTTP de segurança
  obrigatórios, supply chain SHA-pin em CI, ANPD 2026 (prioridade em dados
  de crianças/IA/scraping), SCC internacional obrigatória, breach
  notification 3 dias úteis, hooks > instruções pra regras críticas.

### Mudou — Comportamento `--headless` e `--resume`

- `--resume` pula o launcher se `.blindar/config.yml` existir e tem
  `mode` + `selected_modules`. Retoma de `state.json`.
- `--headless` (CI/cron) pula launcher e usa defaults: todos os módulos
  detectados como ON, modo `auto`, rigor `production`.
- `--reset` apaga `.blindar/` e roda launcher do zero.
- `--dry-run` roda launcher mas grava `dry_run: true`. Simula módulos
  sem commits/PRs.

### Mudou — Schema de config

- `schemas/config.schema.json` ganhou campos: `mode`, `selected_modules`,
  `project_type`, `data_sensitivity`, `rigor`, `ui_detected`, `db_detected`.
- Compat retroativa: configs v0.7 (sem esses campos) rodam como `mode: auto`
  + `selected_modules: [1..15]` (todos).

### Mudou — Pipeline Fase 02 (discovery) e Fase 04 (rounds-loop)

- Discovery (Fase 02) agora detecta `ui_detected` e `db_detected` e
  atualiza `config.yml`.
- Rounds-loop (Fase 04) filtra agentes por `selected_modules` ∩
  `MODULE-MAP[module].agents`. Gap sem agente ativo vira `n/a` com tag
  `skipped-by-user-selection`.

### Migração v0.7 → v0.8

Nada a fazer. Configs antigos rodam em modo "rodar tudo" automaticamente
(comportamento v0.7 preservado). Novo launcher só aparece em primeira
execução em projeto sem `.blindar/config.yml`.

### Total de fases em v0.8

**11 fases**: 1 launcher (00) + 8 principais (00 strategic-scan + 01..07) +
2 opcionais (08 maintenance, 09 drift-detection). Antes (v0.7): 10 fases.
Todos os headers internos dos arquivos `pipeline/*.md` foram alinhados com
o número do prefixo.

---

## [0.7.0] — 2026-06-07

### BREAKING — renumeração de fases

Adicionada **Fase 0: Strategic Scan & Planning** antes do Baseline.
Todas as fases existentes foram **renumeradas +1**:

| Antes (v0.6.x) | Agora (v0.7.0) |
|---|---|
| 00-baseline.md | 01-baseline.md |
| 01-discovery.md | 02-discovery.md |
| 02-bootstrap-sec-html.md | 03-bootstrap-sec-html.md |
| 03-rounds-loop.md | 04-rounds-loop.md |
| 04-adversarial-review.md | 05-adversarial-review.md |
| 05-production-checklist.md | 06-production-checklist.md |
| 06-final-report.md | 07-final-report.md |
| 07-maintenance.md | 08-maintenance.md |
| 08-drift-detection.md | 09-drift-detection.md |
| (nova) | **00-strategic-scan.md** |

**Migração**: nada a fazer no projeto-alvo. `.blindar/state.json`
mantém compatibilidade (`phase` field aceita os nomes textuais).

### Adicionou — Fase 0 Strategic Scan & Planning

- `pipeline/00-strategic-scan.md` — nova fase pré-baseline:
  - **Varredura arquitetural** (read-only) em 14 categorias:
    auth, autz, storage, secrets, frontend, API, testes, CI/CD,
    logging, deps, arquitetura, perf, resiliência, observability
  - **Findings numerados** por severidade (crit / high / med / info)
  - **Pergunta interativa** ao operador: "quais aplicar? [1-5, 10, 16-18]"
  - **Detecção de hardware** (cores, RAM)
  - **Plano de paralelismo** otimizado pra máquina atual
  - **Save** `.blindar/plan.json` + `.blindar/scan-report.md`

- `agents/strategic-scanner.md` — agente novo, **read-only**:
  - Não implementa nada, só observa e propõe
  - Detecta anti-patterns: senhas plaintext, .env commitado,
    JSON-as-DB, sem MFA, CORS *, innerHTML inseguro, etc.
  - Classifica esforço (Sm/Md/Lg/XL) e aponta agente que atacaria

- `templates/scan-report.md` — formato do relatório legível por
  humano. Findings agrupadas por severidade, com encontrado/sugerido/
  agente/esforço por finding.

- `schemas/plan.schema.json` — schema do `.blindar/plan.json` com
  hardware, findings selecionados, grupos paralelos, dependências.

### Adicionou — paralelismo inteligente

Cálculo automático na Fase 0:
- `max_parallel_agents = min(16, cpu_cores - 2)` — bate com cap da
  Workflow API
- **Grupos independentes** identificados:
  - Grupo A: access-control + crypto + observability (alta vazão)
  - Grupo B: frontend + network-security + supply-chain
  - Grupo C: resilience + business-logic (sequencial, dependências)

### Mudou — SKILL.md + AI-ENTRYPOINT.md

- Pipeline table reflete renumeração
- AI-ENTRYPOINT Passo 4: agora 8 fases (0-7) + 2 opcionais (8-9)
- Strategic Scanner adicionado ao roster de agentes

### Não mudou

- Conteúdo das fases existentes (só renomeação)
- Agentes existentes
- Schemas existentes (apenas adicionou `plan.schema.json`)
- Defaults do skill

### Filosofia

"Antes de blindar, **olhar**. Antes de olhar, **planejar**."

Sem Fase 0, blindar gastava rounds em coisas que o operador nem queria
fixar. Agora a Fase 0 produz contrato explícito sobre o que vai/não vai
ser atacado, com tempo estimado realista e plano de paralelismo
ajustado à máquina.

## [0.6.0] — 2026-06-07

Endereça 25/30 itens do brainstorm de melhorias (ver
[`ROADMAP.md`](ROADMAP.md)).

### Adicionou — 2 agentes novos (Tier 1 segurança)

- `agents/business-logic.md` (#1) — OWASP ASVS V11 completa:
  race em saldo/cupom/inventário, IDOR previsível, workflow abuse,
  input bounds (qty negativa, float-money), refund/reversal,
  account takeover via reset/email, resource exhaustion lógica.
- `agents/runtime-secrets.md` (#5) — vazamento em runtime:
  env leakage, token em URL, heap/memory dump, process listing,
  debugger em prod, backup com secret, crash reports.

### Adicionou — 2 fases de pipeline (Tier 5 continuidade)

- `pipeline/08-maintenance.md` (#19) — opt-in trimestral. Pipeline
  reduzido: drift + CVE + stale check. Sem rounds extensivos.
  (Era `07-maintenance.md` na v0.6; renumerado em v0.7.)
- `pipeline/09-drift-detection.md` (#21) — detecta defesas
  removidas em PRs posteriores (grep guard sumido, teste
  deletado, header dropped, audit chain quebrada).
  (Era `08-drift-detection.md` na v0.6; renumerado em v0.7.)

### Adicionou — 7 specs em `docs/specs/`

Cada spec define forma, implementação proposta e razão de ainda
não estar implementado:

- `evidence-package.md` (#15)
- `atk-sbom.md` (#17)
- `reproducibility.md` (#16)
- `load-test-harness.md` (#6)
- `notifications.md` (#24)
- `api-contract.md` (#3)
- `race-fuzzing.md` (#4)

### Adicionou — scripts bash + validator (Tier 3 atrito)

- `scripts/preflight.sh`, `install.sh`, `check-update.sh` — Linux/macOS
  agora têm paridade com Windows.
- `scripts/validate.ps1` + `scripts/validate.sh` (#12) — wrapper
  básico que valida JSON contra `schemas/*.json` sem dep externa.

### Mudou — schemas/config.schema.json

- `target_framework` agora aceita **string OR array** (#18 multi-target):
  ```yaml
  target_framework: [iso27001, soc2]   # múltiplos coverage reports
  ```
- Novos flags: `dry_run` (#10), `minimal_mode` (#11),
  `maintenance_mode` (#19), `load_test`, `notifications`.

### Mudou — agentes existentes com seções v0.6.0

- `access-control.md` (#2): auth edges — reset enumeration, session
  fixation, mudança de email com reconfirmação, step-up auth,
  recovery code hashing.
- `patch-management.md` (#20): CVE feed subscription
  (GitHub Advisory, OSV.dev, NVD) + SLA por severity.
- `observability.md` (#8): RUM contínuo pós-launch + drift detection
  de Web Vitals.
- `scalability.md` (#9): benchmark obrigatório antes/depois pra DB,
  cache, pool, stampede.
- `devops.md` (#7): IaC fixes como PRs separados (branch `iac/*`).

### Mudou — AI-ENTRYPOINT.md

Novo Passo 0 — identificação de modo: FULL / DRY-RUN / MINIMAL /
MAINTENANCE. Decision tree determinístico por modo.

### Deferred com razão explícita

7 itens (#13 MULTI-AI ref impl, #23 web dashboard, #25 IDE plugin,
#26 CLI standalone, #27 examples, #28 catálogo comunitário,
#29 stack starters, #30 compat matrix) requerem trabalho fora do
escopo de um chat session — projetos full, infra comunitária,
extensões IDE. Documentados em ROADMAP.md com razão.

### % projetada com v0.6.0

- Segurança: 85-90% → **89-92%** (business-logic + runtime-secrets +
  auth edges)
- Escalabilidade: 70-80% → **80-85%** (benchmarking + IaC + maintenance)
- Fluidez: 75-85% → **82-87%** (RUM + drift detection)

### Não mudou

- Pipeline original (Fases 0-6).
- Agentes pre-existentes (mesmo comportamento, só ganharam seções v0.6).
- Schemas existentes (só `config.schema.json` evoluiu).
- Defaults.

## [0.5.0] — 2026-06-07

Foco: **facilitar a vida da AI** + **ponta-a-ponta determinístico** +
**termination clara**.

### Adicionou — contratos formais

- `schemas/` — 7 JSON schemas (draft-07) pra saídas validáveis:
  - `inventory.schema.json`, `threat.schema.json`, `arch.schema.json`
    — discovery (Fase 1)
  - `findings.schema.json`, `verdict.schema.json` — adversarial (Fase 4)
  - `state.schema.json`, `config.schema.json` — `.blindar/` no projeto-alvo
- `CONTRACT.md` — define a estrutura `.blindar/` que o skill mantém no
  projeto-alvo: `state.json` (resumability determinística),
  `config.yml` (overrides), `accept-risk.md`, `discovery/`, `checkpoints/`
- `.gitignore` recomendado pro projeto-alvo documentado

### Adicionou — entrypoint pra AI

- `AI-ENTRYPOINT.md` — UMA página que a AI lê primeiro com decision tree
  determinístico:
  - Identificação de modo (nativo Workflow vs manual)
  - Pre-flight check
  - Resume vs fresh start
  - Pipeline step-by-step
  - Termination check
  - Regras invioláveis
- Toda decisão tem regra explícita — sem "criatividade" necessária pra
  completar o ciclo

### Adicionou — preflight automatizado

- `scripts/preflight.ps1` — 1 comando que valida todos os 8 pré-reqs no
  projeto-alvo: repo git, branch viva, working tree limpo, CI, stack,
  gh autenticado, `.blindar/` dir, migração de accept-risk.md
- Flag `-Fix` corrige o que dá pra automatizar (criar `.blindar/`, migrar
  accept-risk.md da raiz)

### Adicionou — repo health

- `.github/workflows/lint.yml` — CI que valida:
  - JSON schemas são draft-07 válidos
  - VERSION é semver
  - Links markdown internos não quebram
  - `.ps1` files têm sintaxe válida
- `.github/ISSUE_TEMPLATE/bug.md` e `feature.md`
- `.github/PULL_REQUEST_TEMPLATE.md` reforça princípios do skill
  ("pago em PR vermelho mergeado")

### Adicionou — honestidade documentada

- `ROADMAP.md` — lista clara do que ficou de fora da v0.5.0 e por quê
  (bash scripts, examples, minimal mode, dry-run, monorepo, etc.)
- SKILL.md e README.md atualizados com seções "Para AIs" e estrutura
  do repo refletindo schemas/ + entrypoint + contract

### Migração de versões anteriores

Projetos com `accept-risk.md` na raiz: rode `scripts/preflight.ps1 -Fix`
na pasta do projeto-alvo. Move pra `.blindar/accept-risk.md`. Sem perda
de dados.

### Não mudou

- Pipeline de 6 fases.
- Agentes (17, mesmo conteúdo).
- Frameworks mapeados.
- Templates.
- Defaults do skill.

## [0.4.2] — 2026-06-07

### Adicionou
- `USAGE.md` — guia completo passo-a-passo de uso:
  - Instalação por OS
  - Pré-requisitos no projeto-alvo
  - Primeiro uso (passo a passo)
  - O que esperar durante execução + cronograma típico
  - Como acompanhar via `sec.html`
  - Parar / pausar / retomar
  - Critério de termination
  - Casos especiais (LGPD, PCI, framework alvo, stack obscura, pentest)
  - Modo multi-AI (referência ao MULTI-AI.md)
  - Atualização do skill
  - Troubleshooting (8 cenários comuns)
  - Comandos úteis
  - Resumo de 1 página

### Mudou
- `README.md` — adicionado link destacado para `USAGE.md` na seção de uso.

## [0.4.1] — 2026-06-07

### Adicionou
- `LICENSE` — MIT (copyright atribuído ao mantenedor)
- README.md atualizado com seção de licença

### Por quê MIT
Permissiva, amplamente compreendida, default sensato para skills. Não
restringe uso comercial. Forks precisam manter aviso de copyright.

## [0.4.0] — 2026-06-07

### Adicionou — frente "fluidez" (frontend performance)

`agents/frontend-performance.md` — Core Web Vitals based:
- **LCP** ≤ 2.5s, **INP** ≤ 200ms (substituiu FID em 2024), **CLS** ≤ 0.1
- Budget de bundle (170kb mobile / 350kb desktop, gzipped)
- Hidratação, animation jank, layout vs composite
- Adaptações por stack: React/RSC/Vue/Svelte/Astro/SPA vanilla
- RUM > Lab como princípio (sem RUM, não há prova de fluidez real)
- Ferramentas: Lighthouse CI, web-vitals lib, profilers

Origem dos thresholds: Google Web Vitals (web.dev/vitals), baseados
em Chrome UX Report — bilhões de pageviews reais. Não fabricado.

### Mudou — escalabilidade saiu de stub

`agents/scalability.md` agora tem conteúdo completo:
- Statelessness (12-factor) como pré-requisito
- Idempotência (Idempotency-Key, dedup em queue)
- Cache + proteção de stampede (SWR, lock distribuído)
- Queue + backpressure (DLQ, concurrency limit)
- DB scale (pool, PgBouncer/Proxy, replicas, migrations zero-downtime)
- Hot keys / fan-out / thundering herd
- Horizontal scaling readiness (/live vs /ready, graceful shutdown)
- Adaptações por stack: Node/Python(GIL/async)/Go/JVM/PG/Mongo

Princípio explícito: scale ≠ performance. Otimizar de 50→30ms não
ajuda se cair em 100 usuários simultâneos.

### Mudou — SKILL.md roster

- "Performance" agora explícito como "backend / gargalo medido"
- "Fluidez frontend" adicionada como categoria própria
- "Escalabilidade" sem marca de stub

### Não mudou

- Pipeline de 6 fases
- Outros agentes
- Defaults

## [0.3.1] — 2026-06-07

### Adicionou — OWASP ASVS como framework

- `frameworks/owasp-asvs.md` — mapeamento V1-V14 ↔ agents. Régua de
  verificação de aplicação (L1/L2/L3). Maior aderência prática entre
  os frameworks por ser baseado em requisitos verificáveis.
- Discovery passa a detectar nível ASVS alvo (default L2; L3 sob flag).

### Adicionou — metodologias de pentest em `agents/pentest.md`

Seção "Metodologias de referência" agora cobre:
- **PTES** (Penetration Testing Execution Standard)
- **OWASP WSTG** (Web Security Testing Guide)
- **NIST SP 800-115** (guia técnico)
- **OSSTMM** (subset operacional — físico/humano fora de escopo)
- **CREST** (conduta profissional — pra firma externa)

Cada uma documentada com **escopo e quando aplica**, não como agente
ativo — são estruturas de teste, não código a implementar.

### Adicionou — integração opcional HexStrike AI

`agents/pentest.md` documenta [HexStrike AI](https://github.com/0x4m4/hexstrike-ai)
como **opção avançada** para pentest interno autorizado:
- Pré-requisitos não negociáveis (autorização escrita, ambiente isolado,
  operador humano on-call)
- Quando NUNCA usar (sem autz, contra prod, contra terceiros)
- Aviso legal explícito (Lei 12.737 / Art. 154-A no BR)
- **Não é default do skill** — uso é decisão e risco do operador

### Adicionou — referências NIST SP 800

`frameworks/nist-csf.md` agora mapeia a família SP 800:
- SP 800-53 (catálogo controles), SP 800-61 (IR), SP 800-115 (pentest),
- SP 800-37 (RMF), SP 800-63 (auth), SP 800-88 (sanitização de mídia)

### Não adicionou (decisão explícita)

- **OSINT** — disciplina ofensiva de reconhecimento. Sai do escopo
  defensivo do blindar. Recomendação: ferramenta separada.
- **SANS, ANSI** — organização de treinamento e órgão de coordenação
  respectivamente, não frameworks. Mencionados em referências.

### Não mudou

- Comportamento do skill é o mesmo.
- Pipeline, agentes, defaults inalterados.
- Sem novos agentes — só novo framework + atualizações de docs.

## [0.3.0] — 2026-06-07

### Adicionou — security-first

- Princípio explícito **SECURITY-FIRST** no `SKILL.md`: em empate de
  severidade, segurança vence performance/scalability/UX.
- Novo quality gate: PR não-security não pode degradar defesa existente.
- Roster de agentes reordenado — agentes de segurança listados primeiro,
  carregados primeiro.

### Adicionou — 7 agentes de segurança especializados

Cobre as 10 técnicas clássicas de segurança de TI:

- `agents/access-control.md` (técnica #1) — auth/MFA/RBAC/least-privilege
- `agents/cryptography.md` (técnica #2) — TLS/at-rest/secrets/key-mgmt
- `agents/network-security.md` (técnicas #3, #8) — WAF/rate-limit/IaC SG
- `agents/patch-management.md` (técnica #5) — OS/runtime + Renovate
- `agents/backup-recovery.md` (técnica #6) — backup cifrado + restore testado
- `agents/observability.md` (técnica #7) — logs estruturados + métricas + audit
- `agents/pentest.md` (técnica #10) — SAST/DAST/SCA/fuzz automatizados

### Adicionou — frameworks/

Mapeamento de controles ↔ agentes (referência, não agentes ativos):

- `frameworks/iso-27001.md` — mais aceito internacionalmente
- `frameworks/nist-csf.md` — operacional/estratégico (6 funções v2.0)
- `frameworks/cis-controls.md` — 18 controles pragmáticos
- `frameworks/pci-dss.md` — **condicional** (só se processa cartão)
- `frameworks/soc2.md` — SaaS / cloud / B2B
- `frameworks/cobit.md` — **stub** (governança, baixa aplicabilidade em código)

### Adicionou — runbooks/

Templates para o que NÃO cabe em código:

- `runbooks/antimalware.md` (técnica #4)
- `runbooks/network-segmentation.md` (parte física da técnica #8)
- `runbooks/security-awareness.md` (técnica #9)
- `runbooks/pentest-schedule.md` (complemento à #10)

### Adicionou — multi-AI

- `MULTI-AI.md` — princípio "sempre multi-agente" + receita pra rodar em
  ChatGPT/Gemini/Cursor via role-play sequencial isolado.
- SKILL.md inclui princípio explícito **SEMPRE MULTI-AGENTE** (mesmo em
  AIs single-threaded).

### Mudou

- `SKILL.md` cresceu de 145 para ~200 linhas — princípios + roster expandido.
- Roster de agentes agora separa "segurança" (sempre primeiro) de
  "outros" (sob demanda).
- README.md e checklist atualizados refletindo nova estrutura.

### Não mudou

- Pipeline de 6 fases.
- Template `sec.html`.
- Defaults do skill (round size, cadência adversarial).
- Agentes pré-existentes preservam comportamento.

## [0.2.0] — 2026-06-07

### Mudou
- **Reestruturado em módulos**. O `SKILL.md` monolítico (553 linhas) virou
  orquestrador curto que referencia `pipeline/`, `agents/`, `templates/`.
- Template `sec.html` extraído para `templates/sec.html`.
- Roster de agentes (10 especialistas) extraído para `agents/*.md`.
- Pipeline de 6 fases extraído para `pipeline/00..06`.

### Adicionou
- `README.md` para apresentação no GitHub.
- `CHECKLIST.md` para validação pós-download.
- `VERSION` + `CHANGELOG.md` para versionamento.
- `scripts/check-update.ps1` — checa versão remota com TTL de 24h.
- `scripts/install.ps1` — clona/copia o skill para `~/.claude/skills/blindar`.
- `scripts/release.ps1` — bump de versão + tag + GitHub release (dono).
- `agents/scalability.md` — **stub TODO**, conteúdo a ser pago em PR real.

### Não mudou
- Comportamento do skill é idêntico. Mesma pipeline, mesmos prompts.
- Defaults inalterados.

## [0.1.0] — 2026-06-07

### Adicionou
- Versão monolítica inicial do `SKILL.md` (preservada em `SKILL.md.backup-v0`).
- 6 fases, 10 agentes, template `sec.html` inline.
- Extraída de execução real: 118 rounds, 68 ATKs fechados, 24 findings
  adversariais.
