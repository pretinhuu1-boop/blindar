# blindar — prompts por fase

Guia para rodar o blindar **um módulo por vez**, em vez do pipeline inteiro de
uma vez. Cada fase é um prompt copiável, independente, com critério de pronto.

Por que fatiar: o pipeline completo é uma sessão longa onde tudo compete por
atenção e o contexto satura. Um módulo por prompt dá auditoria mais profunda,
diff menor, e você decide entre um e outro se vale continuar.

**Como usar:** abra o projeto, cole o prompt da fase, deixe terminar, revise o
diff, commite, passe para a próxima. Pule as fases que não se aplicam — cada
uma diz quando pular.

Cada prompt de correção carrega um **ciclo** dentro dele: roda o check,
corrige, **re-roda o mesmo check para provar que o achado sumiu**, e repete
até fechar. Ele também carrega a condição de parada — se duas rodadas seguidas
não reduzirem a contagem de crit+high, ele para e explica o que travou, em vez
de insistir. As fases de diagnóstico (baseline, product evolution, recon,
pentest ativo) não têm ciclo porque não corrigem nada.

---

## Fase 0 — Pré-requisitos (uma vez por máquina)

O blindar depende de `rg` e `jq`. **Sem `jq`, o `check-termination.sh` conta os
findings como vazio e declara o projeto pronto para produção independente do
que encontrou** — o pior modo de falha possível. Confira antes de qualquer
coisa:

```bash
command -v rg && rg --version | head -1; command -v jq && jq --version
```

Faltando no Windows:

```bash
winget install BurntSushi.ripgrep.MSVC; winget install jqlang.jq
```

E instale os checks no projeto-alvo (cria `scripts/blindar/`):

```bash
bash ~/.claude/skills/blindar/scripts/install-deterministic-checks.sh
```

> Se o projeto já tinha essa pasta de uma rodada antiga, **reinstale**. A cópia
> em `scripts/blindar/` fica congelada na versão do dia da instalação e não
> recebe correções automaticamente.

---

## Fase 1 — Baseline: mapa e prova de que a app sobe

Módulos 1 e 18. Sem isso as fases seguintes auditam no escuro.

```
Use o blindar, módulos 1 e 18 apenas.

1. Rode o graph-builder e monte o grafo do projeto em .blindar/graph.json:
   endpoints, superfície externa vs interna, arestas entre módulos.
2. Rode o strategic-scanner: qual é a stack real, tipo de projeto, sensibilidade
   dos dados, se há UI, banco, fila, container, orquestrador.
3. Rode o smoke-runtime: prove que a aplicação SOBE e responde. Se ela não sobe,
   pare tudo e me diga o que falta — auditar código de app que não roda é
   desperdício.
4. Rode os checks de runtime: deps-sync, entrypoint-cmd, datetime-tz,
   worker-jobs, alembic-health, notnull-no-default, ratelimit-response.

Ao final me entregue: a stack detectada, o inventário de superfície externa, e
a lista de módulos do blindar que se aplicam a ESTE projeto (com justificativa
de quais não se aplicam). Não corrija nada ainda — esta fase é diagnóstico.
```

**Pronto quando:** existe `.blindar/graph.json`, a app comprovadamente sobe, e
você tem a lista de módulos aplicáveis.

---

## Fase 2 — Segurança aplicacional core

Módulo 2, o maior (19 agentes). **Nunca pule.**

```
Use o blindar, módulo 2 apenas (segurança aplicacional core).

Audite com os agentes: access-control, cryptography, business-logic,
runtime-secrets, security, auth-premium, prototype-pollution, file-uploads,
tenant-isolation-tests. Se o projeto usa LLM, inclua também ai-llm-safety,
prompt-injection-defense, llm-system-prompt-leak, vector-db-security,
fine-tune-data-leak, rag-quality.

Para cada achado:
1. Prove que é real — mostre o caminho de exploração, não só o padrão casado.
2. Corrija na causa raiz, não no sintoma.
3. Escreva um teste que FALHA antes da correção e passa depois (happy, edge, e
   um caso de ataque).
4. Adicione um guard estático que impeça a regressão.

Rode a suíte antes de cada commit. Um commit por classe de vulnerabilidade,
não um commit gigante.

Regras: não introduza dependência nova sem justificar; não enfraqueça um check
para ficar verde; se um achado for falso-positivo, diga por que e adicione a
supressão em .blindar/intelligence.yml com o motivo escrito.

Ao final: quantos crit/high/med, quais foram corrigidos, quais ficaram e por quê.

CICLO — repita até fechar:
1. Rode os checks desta fase e liste os achados por severidade.
2. Corrija um grupo por vez, na causa raiz.
3. RODE O MESMO CHECK DE NOVO e prove que o achado sumiu. Não confie na
   correção sem re-verificar — corrigir e assumir que funcionou é como o
   blindar ficou 7 semanas reportando "passed" sem varrer arquivo.
4. Rode a suíte completa. Verde antes de commitar.
5. Sobrou achado? Volte ao passo 2.

Feche a fase quando: 0 crit, e cada high restante registrado em
accept-risk.md com justificativa escrita.

Pare ANTES disso se duas rodadas seguidas não reduzirem a contagem de
crit+high — nesse caso me diga o que está travando, em vez de seguir
tentando. Progresso zero repetido é sinal de que o problema é outro.

Nunca feche a fase suprimindo achado no .blindar/intelligence.yml sem motivo
escrito, nem afrouxando o check.
```

**Pronto quando:** 0 crit. Highs restantes precisam estar em `accept-risk.md`
com justificativa assinada.

---

## Fase 3 — Rede, API e contratos

Módulo 4. **Pule se** o projeto não expõe API.

```
Use o blindar, módulo 4 apenas (rede & API).

Agentes: network-security, api-design, api-surface-isolation. Inclua payments
se houver cobrança, realtime se houver WebSocket/SSE, api-gateway se houver
gateway, graphql e grpc-internal conforme o caso.

Foco:
- CORS, CSRF, rate limit por rota e por identidade (não só por IP)
- Superfície interna exposta sem querer (rota admin acessível de fora)
- Contrato: OpenAPI existe e bate com o código? Versionamento? Erros padronizados?
- Paginação obrigatória em toda listagem
- Idempotência em operações de escrita que podem ser retentadas

Corrija, teste cada correção com um caso real de request, e rode a suíte.
Me diga também o que você NÃO conseguiu testar sem ambiente de homolog.

Critério extra desta fase: a superfície externa tem que bater com o que o
.blindar/graph.json diz que deveria ser pública, e TODA listagem tem que
paginar. Confira os dois explicitamente antes de fechar.

CICLO — repita até fechar:
1. Rode os checks desta fase e liste os achados por severidade.
2. Corrija um grupo por vez, na causa raiz.
3. RODE O MESMO CHECK DE NOVO e prove que o achado sumiu. Não confie na
   correção sem re-verificar — corrigir e assumir que funcionou é como o
   blindar ficou 7 semanas reportando "passed" sem varrer arquivo.
4. Rode a suíte completa. Verde antes de commitar.
5. Sobrou achado? Volte ao passo 2.

Feche a fase quando: 0 crit, e cada high restante registrado em
accept-risk.md com justificativa escrita.

Pare ANTES disso se duas rodadas seguidas não reduzirem a contagem de
crit+high — nesse caso me diga o que está travando, em vez de seguir
tentando. Progresso zero repetido é sinal de que o problema é outro.

Nunca feche a fase suprimindo achado no .blindar/intelligence.yml sem motivo
escrito, nem afrouxando o check.
```

**Pronto quando:** superfície externa bate com o que o grafo diz que deveria
ser pública, e toda listagem pagina.

---

## Fase 4 — Frontend hardening

Módulo 3. **Pule se** não há UI.

```
Use o blindar, módulo 3 apenas (frontend hardening).

Agentes: frontend, client-open-redirect.

Foco: CSP sem unsafe-inline (nonce ou hash), XSS em dangerouslySetInnerHTML /
v-html / innerHTML, SRI em script externo, Trusted Types, open redirect no
cliente, postMessage sem checagem de origem, e secret vazando no bundle.

Para CSP: não me entregue uma policy permissiva que "passa no check". Se
precisar de unsafe-inline para funcionar hoje, diga isso explicitamente e
proponha o caminho para remover.

Corrija, teste, rode a suíte.

CICLO — repita até fechar:
1. Rode os checks desta fase e liste os achados por severidade.
2. Corrija um grupo por vez, na causa raiz.
3. RODE O MESMO CHECK DE NOVO e prove que o achado sumiu. Não confie na
   correção sem re-verificar — corrigir e assumir que funcionou é como o
   blindar ficou 7 semanas reportando "passed" sem varrer arquivo.
4. Rode a suíte completa. Verde antes de commitar.
5. Sobrou achado? Volte ao passo 2.

Feche a fase quando: 0 crit, e cada high restante registrado em
accept-risk.md com justificativa escrita.

Pare ANTES disso se duas rodadas seguidas não reduzirem a contagem de
crit+high — nesse caso me diga o que está travando, em vez de seguir
tentando. Progresso zero repetido é sinal de que o problema é outro.

Nunca feche a fase suprimindo achado no .blindar/intelligence.yml sem motivo
escrito, nem afrouxando o check.
```

---

## Fase 5 — Supply chain

Módulo 5. Roda em qualquer projeto.

```
Use o blindar, módulo 5 apenas (supply chain).

Agentes: supply-chain, patch-management, sbom-slsa. Rode osv-scanner e trivy se
estiverem instalados; se não estiverem, diga isso em vez de pular em silêncio.

Foco: dependência com CVE conhecida, lockfile ausente ou dessincronizado,
dependência abandonada, typosquatting, script de postinstall, e geração de SBOM.

Ao corrigir: separe o que é bump seguro do que é breaking change. Não faça
upgrade major junto com hardening — isso vira um diff impossível de revisar.
Liste os majors como trabalho separado.

CICLO — repita até fechar:
1. Rode os checks desta fase e liste os achados por severidade.
2. Corrija um grupo por vez, na causa raiz.
3. RODE O MESMO CHECK DE NOVO e prove que o achado sumiu. Não confie na
   correção sem re-verificar — corrigir e assumir que funcionou é como o
   blindar ficou 7 semanas reportando "passed" sem varrer arquivo.
4. Rode a suíte completa. Verde antes de commitar.
5. Sobrou achado? Volte ao passo 2.

Feche a fase quando: 0 crit, e cada high restante registrado em
accept-risk.md com justificativa escrita.

Pare ANTES disso se duas rodadas seguidas não reduzirem a contagem de
crit+high — nesse caso me diga o que está travando, em vez de seguir
tentando. Progresso zero repetido é sinal de que o problema é outro.

Nunca feche a fase suprimindo achado no .blindar/intelligence.yml sem motivo
escrito, nem afrouxando o check.
```

---

## Fase 6 — Banco de dados, backup e recuperação

Módulo 7. **Pule se** não há banco.

```
Use o blindar, módulo 7 apenas (dados).

Agentes: db-architect, backup-recovery. Inclua multi-region se houver mais de
uma região, data-warehouse-etl se houver pipeline analítico.

Foco:
- Índice faltando em coluna de filtro/join quente; índice redundante
- N+1 em caminho de request
- Migration destrutiva sem rollback
- Coluna NOT NULL sem default adicionada em tabela com dados
- Soft delete consistente
- Backup: existe, é testado, e o RESTORE já foi exercitado? Backup não testado
  não é backup — se nunca foi restaurado, reporte como achado.
- RPO e RTO declarados

Corrija o que é seguro corrigir. Migration destrutiva: proponha, NÃO execute.

CICLO — repita até fechar:
1. Rode os checks desta fase e liste os achados por severidade.
2. Corrija um grupo por vez, na causa raiz.
3. RODE O MESMO CHECK DE NOVO e prove que o achado sumiu. Não confie na
   correção sem re-verificar — corrigir e assumir que funcionou é como o
   blindar ficou 7 semanas reportando "passed" sem varrer arquivo.
4. Rode a suíte completa. Verde antes de commitar.
5. Sobrou achado? Volte ao passo 2.

Feche a fase quando: 0 crit, e cada high restante registrado em
accept-risk.md com justificativa escrita.

Pare ANTES disso se duas rodadas seguidas não reduzirem a contagem de
crit+high — nesse caso me diga o que está travando, em vez de seguir
tentando. Progresso zero repetido é sinal de que o problema é outro.

Nunca feche a fase suprimindo achado no .blindar/intelligence.yml sem motivo
escrito, nem afrouxando o check.
```

---

## Fase 7 — Observabilidade e ciclo de vida do log

Módulo 6. Duas metades distintas — não confunda.

```
Use o blindar, módulo 6 apenas.

PARTE A — observability (conteúdo do log):
Log estruturado JSON, correlation_id propagado até os jobs de background,
níveis corretos, PII redigida por helper central, métricas de latência
(p50/p95/p99), error rate e saturação nas rotas críticas, health endpoints
(/live, /ready, /deep), e audit trail para ação privilegiada.

PARTE B — log-ops-retention (ciclo de vida em disco):
Só se aplica se o projeto escreve log em ARQUIVO. Se só usa stdout e há coletor
externo, isso é legítimo — diga e pule a parte B.
Se escreve em arquivo: pasta por dia em UTC, rotação por tamanho, UM ARQUIVO
POR PROCESSO com identificador de instância, streams separados (access, app,
error, security, e um por tipo de job), retenção escalonada, e as cinco guardas
obrigatórias no código que apaga (regex exata de data, realpath dentro do
LOG_DIR, lstat para não seguir symlink, piso rígido que nunca apaga hoje nem
ontem, e registro de bytes liberados).

Regra dura: NÃO crie uma segunda política de redação. Reuse a que existe. Se
não existir nenhuma, isso é achado — reporte e pare, não improvise.

Deixe explícito em código e em doc que esses arquivos são diagnóstico
operacional e NÃO são a trilha de auditoria.

Teste obrigatório: um fluxo real que grava log, depois LÊ os arquivos
produzidos e falha se encontrar token, cookie, header de autorização, corpo de
request, CPF, cartão ou nome. Redação sem teste é promessa.

Critério extra desta fase: esse teste tem que EXISTIR e PASSAR. Sem ele a
fase não fecha, mesmo com 0 crit.

CICLO — repita até fechar:
1. Rode os checks desta fase e liste os achados por severidade.
2. Corrija um grupo por vez, na causa raiz.
3. RODE O MESMO CHECK DE NOVO e prove que o achado sumiu. Não confie na
   correção sem re-verificar — corrigir e assumir que funcionou é como o
   blindar ficou 7 semanas reportando "passed" sem varrer arquivo.
4. Rode a suíte completa. Verde antes de commitar.
5. Sobrou achado? Volte ao passo 2.

Feche a fase quando: 0 crit, e cada high restante registrado em
accept-risk.md com justificativa escrita.

Pare ANTES disso se duas rodadas seguidas não reduzirem a contagem de
crit+high — nesse caso me diga o que está travando, em vez de seguir
tentando. Progresso zero repetido é sinal de que o problema é outro.

Nunca feche a fase suprimindo achado no .blindar/intelligence.yml sem motivo
escrito, nem afrouxando o check.
```

**Pronto quando:** o teste de dado sensível existe e passa.

---

## Fase 8 — Compliance

Módulo 8. **Pule se** não há dado pessoal nem obrigação regulatória.

```
Use o blindar, módulo 8 apenas (compliance).

Escolha os agentes pelo que se aplica: compliance-lgpd-br (Brasil),
compliance-gdpr (UE), compliance-hipaa (saúde EUA), compliance-pci-deep
(cartão), fintech-banking-br, healthtech-fhir, ecom-checkout-conversion.

Foco: base legal por finalidade, consentimento granular e revogável, direitos
do titular (acesso, correção, portabilidade, eliminação) implementados de fato
e não só na política, retenção com prazo por categoria, registro de operações,
e trilha de auditoria imutável separada do log operacional.

Me diga claramente o que é lacuna TÉCNICA (posso corrigir) e o que é lacuna
JURÍDICA/PROCESSUAL (precisa de decisão humana). Não escreva política de
privacidade — isso não é trabalho de código.

CICLO — repita até fechar:
1. Rode os checks desta fase e liste os achados por severidade.
2. Corrija um grupo por vez, na causa raiz.
3. RODE O MESMO CHECK DE NOVO e prove que o achado sumiu. Não confie na
   correção sem re-verificar — corrigir e assumir que funcionou é como o
   blindar ficou 7 semanas reportando "passed" sem varrer arquivo.
4. Rode a suíte completa. Verde antes de commitar.
5. Sobrou achado? Volte ao passo 2.

Feche a fase quando: 0 crit, e cada high restante registrado em
accept-risk.md com justificativa escrita.

Pare ANTES disso se duas rodadas seguidas não reduzirem a contagem de
crit+high — nesse caso me diga o que está travando, em vez de seguir
tentando. Progresso zero repetido é sinal de que o problema é outro.

Nunca feche a fase suprimindo achado no .blindar/intelligence.yml sem motivo
escrito, nem afrouxando o check.
```

---

## Fase 9 — Performance

Módulo 9. **Pule se** ainda não há tráfego real ou meta de latência.

```
Use o blindar, módulo 9 apenas (performance).

Agentes: performance, db-architect, cdn-strategy, redis-patterns.

Regra que vem antes de tudo: MEÇA antes de otimizar. Se não houver número de
baseline, estabeleça um primeiro. Otimização sem medição é chute.

Foco: query lenta no caminho quente, cache com chave errada ou sem
invalidação, cache stampede, payload grande sem compressão, ausência de CDN
para estático, e connection pool mal dimensionado.

Para cada otimização, mostre o antes e o depois com número. Se não melhorou,
reverta — complexidade sem ganho é dívida.

CICLO — repita até fechar:
1. Rode os checks desta fase e liste os achados por severidade.
2. Corrija um grupo por vez, na causa raiz.
3. RODE O MESMO CHECK DE NOVO e prove que o achado sumiu. Não confie na
   correção sem re-verificar — corrigir e assumir que funcionou é como o
   blindar ficou 7 semanas reportando "passed" sem varrer arquivo.
4. Rode a suíte completa. Verde antes de commitar.
5. Sobrou achado? Volte ao passo 2.

Feche a fase quando: 0 crit, e cada high restante registrado em
accept-risk.md com justificativa escrita.

Pare ANTES disso se duas rodadas seguidas não reduzirem a contagem de
crit+high — nesse caso me diga o que está travando, em vez de seguir
tentando. Progresso zero repetido é sinal de que o problema é outro.

Nunca feche a fase suprimindo achado no .blindar/intelligence.yml sem motivo
escrito, nem afrouxando o check.
```

---

## Fase 10 — Fluidez, acessibilidade e SEO

Módulo 10 (16 agentes). **Pule se** não há UI. É a fase mais longa — considere
rodar em dois prompts.

```
Use o blindar, módulo 10 apenas. Rode em duas partes.

PARTE 1 — o que quebra a experiência:
frontend-performance (Core Web Vitals: LCP, INP, CLS), responsive-a11y (WCAG
2.2 AA, navegação por teclado, contraste, foco visível), session-timeout-ux,
onboarding-ux, state-cache-data.

PARTE 2 — o que amplia alcance:
seo-marketing-meta, i18n-tz, pwa-installable, search-quality,
push-notifications, govtech-acessibilidade (se for setor público).

Em acessibilidade não aceite "tem aria-label" como prova. Teste navegação real
por teclado e a ordem de foco.

Corrija, meça o antes/depois dos Web Vitals, rode a suíte.

CICLO — repita até fechar:
1. Rode os checks desta fase e liste os achados por severidade.
2. Corrija um grupo por vez, na causa raiz.
3. RODE O MESMO CHECK DE NOVO e prove que o achado sumiu. Não confie na
   correção sem re-verificar — corrigir e assumir que funcionou é como o
   blindar ficou 7 semanas reportando "passed" sem varrer arquivo.
4. Rode a suíte completa. Verde antes de commitar.
5. Sobrou achado? Volte ao passo 2.

Feche a fase quando: 0 crit, e cada high restante registrado em
accept-risk.md com justificativa escrita.

Pare ANTES disso se duas rodadas seguidas não reduzirem a contagem de
crit+high — nesse caso me diga o que está travando, em vez de seguir
tentando. Progresso zero repetido é sinal de que o problema é outro.

Nunca feche a fase suprimindo achado no .blindar/intelligence.yml sem motivo
escrito, nem afrouxando o check.
```

---

## Fase 11 — Resiliência e escalabilidade

Módulo 13. **Pule se** o projeto ainda não está em produção.

```
Use o blindar, módulo 13 apenas (resiliência).

Agentes: resilience, scalability, process-resilience, scheduled-jobs,
queue-management, fallback-resilience, event-driven. Inclua chaos-engineering
só se já houver observabilidade madura.

Foco: timeout em TODA chamada externa, retry com backoff e jitter, circuit
breaker, graceful shutdown com SIGTERM e drain de conexão, job agendado que não
duplica sob concorrência, fila com DLQ e política de reprocessamento, e
idempotência em consumidor de evento.

Teste de verdade: derrube a dependência e prove que a degradação é graciosa.
Se não der para testar sem ambiente, diga — não afirme que funciona sem provar.

CICLO — repita até fechar:
1. Rode os checks desta fase e liste os achados por severidade.
2. Corrija um grupo por vez, na causa raiz.
3. RODE O MESMO CHECK DE NOVO e prove que o achado sumiu. Não confie na
   correção sem re-verificar — corrigir e assumir que funcionou é como o
   blindar ficou 7 semanas reportando "passed" sem varrer arquivo.
4. Rode a suíte completa. Verde antes de commitar.
5. Sobrou achado? Volte ao passo 2.

Feche a fase quando: 0 crit, e cada high restante registrado em
accept-risk.md com justificativa escrita.

Pare ANTES disso se duas rodadas seguidas não reduzirem a contagem de
crit+high — nesse caso me diga o que está travando, em vez de seguir
tentando. Progresso zero repetido é sinal de que o problema é outro.

Nunca feche a fase suprimindo achado no .blindar/intelligence.yml sem motivo
escrito, nem afrouxando o check.
```

---

## Fase 12 — Anti-mock e externalização

Módulo 12. **Nunca pule.** É o que separa protótipo de produção.

```
Use o blindar, módulo 12 apenas.

Agentes: mock-killer, config-externalization, content-quality.

Foco: mock, stub e dado fake em caminho de produção; console.log e print
esquecidos; TODO/FIXME sem issue vinculada; botão com onClick vazio; URL, chave
e credencial hardcoded; cor hex fora de design token; e texto voltado ao
usuário com erro de gramática ou tom inconsistente.

Cada mock removido precisa da implementação real OU de uma feature flag
explícita que o desabilite em produção. Não troque mock por outro mock.

CICLO — repita até fechar:
1. Rode os checks desta fase e liste os achados por severidade.
2. Corrija um grupo por vez, na causa raiz.
3. RODE O MESMO CHECK DE NOVO e prove que o achado sumiu. Não confie na
   correção sem re-verificar — corrigir e assumir que funcionou é como o
   blindar ficou 7 semanas reportando "passed" sem varrer arquivo.
4. Rode a suíte completa. Verde antes de commitar.
5. Sobrou achado? Volte ao passo 2.

Feche a fase quando: 0 crit, e cada high restante registrado em
accept-risk.md com justificativa escrita.

Pare ANTES disso se duas rodadas seguidas não reduzirem a contagem de
crit+high — nesse caso me diga o que está travando, em vez de seguir
tentando. Progresso zero repetido é sinal de que o problema é outro.

Nunca feche a fase suprimindo achado no .blindar/intelligence.yml sem motivo
escrito, nem afrouxando o check.
```

---

## Fase 13 — Testes

Módulo 11. **Nunca pule.**

```
Use o blindar, módulo 11 apenas (testes).

Agentes: testing-strategy, functional-e2e, visual-regression.

Foco: cobertura dos caminhos críticos (não perseguir % global — perseguir os
fluxos que geram receita ou tocam dado sensível), teste que testa mock em vez
do código real, teste flaky, ausência de teste de regressão para bug já
corrigido, e E2E dos fluxos principais.

Antes de escrever teste novo: rode a suíte atual e me diga quantos testes
existem, quantos passam, e quais são flaky. Suíte já vermelha vira minha
prioridade antes de qualquer adição.

CICLO — repita até fechar:
1. Rode os checks desta fase e liste os achados por severidade.
2. Corrija um grupo por vez, na causa raiz.
3. RODE O MESMO CHECK DE NOVO e prove que o achado sumiu. Não confie na
   correção sem re-verificar — corrigir e assumir que funcionou é como o
   blindar ficou 7 semanas reportando "passed" sem varrer arquivo.
4. Rode a suíte completa. Verde antes de commitar.
5. Sobrou achado? Volte ao passo 2.

Feche a fase quando: 0 crit, e cada high restante registrado em
accept-risk.md com justificativa escrita.

Pare ANTES disso se duas rodadas seguidas não reduzirem a contagem de
crit+high — nesse caso me diga o que está travando, em vez de seguir
tentando. Progresso zero repetido é sinal de que o problema é outro.

Nunca feche a fase suprimindo achado no .blindar/intelligence.yml sem motivo
escrito, nem afrouxando o check.
```

---

## Fase 14 — DX, entrega e documentação

Módulo 14. Deixe para o fim — é o que consolida.

```
Use o blindar, módulo 14 apenas.

Agentes: devops, documentation-live, feature-flags, email-deliverability,
architect, delivery-bundle, execution-report.

Foco: CI que roda a suíte e bloqueia merge vermelho, pipeline reproduzível,
README que permite alguém subir o projeto do zero sem perguntar nada,
runbook de incidente, variáveis de ambiente documentadas em .env.example,
feature flags com dono e data de remoção, e deliverabilidade de e-mail
(SPF, DKIM, DMARC) se o projeto envia e-mail.

Teste o README literalmente: siga os passos num diretório limpo e me diga onde
travou.

CICLO — repita até fechar:
1. Rode os checks desta fase e liste os achados por severidade.
2. Corrija um grupo por vez, na causa raiz.
3. RODE O MESMO CHECK DE NOVO e prove que o achado sumiu. Não confie na
   correção sem re-verificar — corrigir e assumir que funcionou é como o
   blindar ficou 7 semanas reportando "passed" sem varrer arquivo.
4. Rode a suíte completa. Verde antes de commitar.
5. Sobrou achado? Volte ao passo 2.

Feche a fase quando: 0 crit, e cada high restante registrado em
accept-risk.md com justificativa escrita.

Pare ANTES disso se duas rodadas seguidas não reduzirem a contagem de
crit+high — nesse caso me diga o que está travando, em vez de seguir
tentando. Progresso zero repetido é sinal de que o problema é outro.

Nunca feche a fase suprimindo achado no .blindar/intelligence.yml sem motivo
escrito, nem afrouxando o check.
```

---

## Fase 15 — Pentest e revisão adversarial

Módulo 15. **Rode por último**, depois de tudo corrigido.

```
Use o blindar, módulo 15 apenas (pentest + adversarial).

Agentes: pentest, adversarial-reviewer, proactive-analysis.

Sua tarefa é TENTAR DERRUBAR o que foi feito nas fases anteriores. Trate cada
correção anterior como suspeita:
- A correção resolve a causa ou só o caso do teste?
- O teste passaria se a correção fosse revertida? (se não, o teste não testa nada)
- Há caminho alternativo para o mesmo efeito que a correção não cobre?
- A supressão em intelligence.yml está escondendo achado real?

Para cada correção anterior que você conseguir furar, abra achado novo com o
caminho de exploração. Prefira reportar falso-positivo a deixar passar coisa
real.

Ao final rode o check-termination e me diga se o projeto está pronto:
0 crit e no máximo 2 high aceitos e assinados.

Critério extra desta fase: o check-termination tem que sair com GO. Antes de
confiar nesse resultado, confirme que `jq` está instalado — sem ele o
check conta os findings como vazio e diz GO independente do que existe.

CICLO — repita até fechar:
1. Rode os checks desta fase e liste os achados por severidade.
2. Corrija um grupo por vez, na causa raiz.
3. RODE O MESMO CHECK DE NOVO e prove que o achado sumiu. Não confie na
   correção sem re-verificar — corrigir e assumir que funcionou é como o
   blindar ficou 7 semanas reportando "passed" sem varrer arquivo.
4. Rode a suíte completa. Verde antes de commitar.
5. Sobrou achado? Volte ao passo 2.

Feche a fase quando: 0 crit, e cada high restante registrado em
accept-risk.md com justificativa escrita.

Pare ANTES disso se duas rodadas seguidas não reduzirem a contagem de
crit+high — nesse caso me diga o que está travando, em vez de seguir
tentando. Progresso zero repetido é sinal de que o problema é outro.

Nunca feche a fase suprimindo achado no .blindar/intelligence.yml sem motivo
escrito, nem afrouxando o check.
```

**Pronto quando:** `check-termination.sh` sai com GO. Confira que `jq` está
instalado antes de confiar nesse resultado.

---

## Fases opcionais

### Módulo 16 — Product Evolution

Escopo separado do hardening. Não misture com as fases acima.

```
Use o blindar, módulo 16 apenas (product evolution).

Agentes: api-frontend-coverage, user-journey-simulator, feature-gap-analyzer,
growth-opportunities, product-critic.

Isto NÃO é hardening — é análise de produto. Não corrija segurança aqui.
Me diga: endpoints que o frontend nunca consome, jornadas que quebram na
prática, lacunas em relação ao que o usuário esperaria, e onde o produto perde
gente. Entregue como lista priorizada com esforço estimado, não como código.
```

### Módulo 17 — Recon passivo externo

Precisa de URL pública. Só reconhecimento, sem tocar no alvo.

```
Use o blindar, módulo 17 (attack-recon) contra <URL>.

Somente recon PASSIVO: headers, tecnologias expostas, subdomínios, certificados,
arquivos esquecidos em caminho previsível, metadados. Não envie payload, não
teste vulnerabilidade, não faça brute force.

Me diga o que um atacante descobre sobre este alvo sem tocar nele.
```

### Módulo 19 — Pentest ativo

**Exige autorização escrita.** Só contra alvo que você controla ou tem
permissão documentada.

```
Use o blindar, módulo 19 (pentest-active) contra <URL>.
Autorização: <arquivo ou referência da autorização>.

Payloads reais contra o alvo autorizado. Pare imediatamente se qualquer
resposta indicar que o alvo não é o esperado.
```

---

## Ordem recomendada

```
0 pré-requisitos → 1 baseline → 2 segurança core → 3 API → 4 frontend
→ 5 supply chain → 6 dados → 7 observabilidade → 8 compliance
→ 9 performance → 10 fluidez → 11 resiliência → 12 anti-mock
→ 13 testes → 14 DX/entrega → 15 pentest final
```

Segurança core vem cedo porque tudo depois depende de a base estar sã. Pentest
vem por último porque ele audita as correções das outras fases. Anti-mock e
testes vêm antes da entrega porque são o que impede o protótipo de vazar para
produção.

---

## Regras que valem em todas as fases

Cole junto com qualquer prompt se quiser reforçar:

```
- Suíte verde antes de cada commit. Se já estiver vermelha, reporte e pare.
- Um commit por classe de problema. Diff pequeno é diff revisável.
- Não enfraqueça um check para ficar verde — isso transforma o gate em teatro.
- Falso-positivo: suprima em .blindar/intelligence.yml COM o motivo escrito.
- Não misture refactor com hardening na mesma rodada.
- Se não conseguir provar que uma correção funciona, diga isso em vez de afirmar.
- Ao final, liste o que ficou de fora e por quê.
```

---

## Lendo os resultados

Cada check escreve `.blindar/results/<check>.json` com `status`
(`passed`/`failed`/`skipped`) e a lista de findings.

```bash
# resumo de todos os checks
for f in .blindar/results/*.json; do
  printf "%-40s %s\n" "$(basename "$f" .json)" "$(jq -r .status "$f")"
done

# todos os crit e high
jq -r '.findings[] | select(.severity=="crit" or .severity=="high")
       | "\(.severity)\t\(.file):\(.line)\t\(.message)"' .blindar/results/*.json
```

`skipped` merece atenção: significa que o check não se aplicou **ou** que uma
ferramenta estava faltando. Confira qual dos dois antes de tratar como aprovado.
