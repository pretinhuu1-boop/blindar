# Book insights — regras acionáveis que agentes consultam

> Destilação de 4 livros de alto valor pro que o blindar faz. **Não é resumo
> dos livros** — é a extração das regras que viram comportamento de agente ou
> check. Cada regra aponta pro agente/check que a materializa.
>
> Curadoria: 2026-07-11. Fonte: pedido do operador (lista de 10 livros).
> Os 6 de arquitetura/código-limpo entraram como princípio, não como check.

Agentes relevantes **devem ler a seção correspondente** antes de rodar.

---

## 1. Segurança em Front-end (Antonio Luis Rossi)

Foco: o lado que o usuário vê. O navegador é território hostil — todo dado que
chega do cliente é suspeito, e todo dado que sai pro DOM é um sink potencial.

| Regra | Severidade | Materializado em |
|---|---|---|
| Todo sink de HTML (`innerHTML`, `dangerouslySetInnerHTML`, `v-html`, `document.write`) exige sanitização (DOMPurify) ou troca por `textContent` | high | [`check-security`](../templates/checks/check-security.sh) |
| `eval`/`new Function` com input do usuário = RCE no cliente | crit | `check-security` |
| Redirect client-side (`location`, `location.href`, `location.assign`, `window.open`) com valor derivado de `location.search`/query/param = **open redirect** (phishing) | high | [`check-client-open-redirect`](../templates/checks/check-client-open-redirect.sh) ⭐ v0.47 |
| Merge/atribuição de objeto vindo do cliente sem bloquear `__proto__`/`constructor`/`prototype` = **prototype pollution** | high | [`check-prototype-pollution`](../templates/checks/check-prototype-pollution.sh) ⭐ v0.47 |
| Token/JWT nunca em `localStorage`/`sessionStorage` (XSS lê) — só cookie `httpOnly`+`SameSite` | crit | [`check-auth-premium`](../templates/checks/check-auth-premium.sh) |
| `target="_blank"` sempre com `rel="noopener noreferrer"` (reverse tabnabbing) | med | [`check-frontend`](../templates/checks/check-frontend.sh) |
| `postMessage`: receptor valida `event.origin`; emissor nunca usa `targetOrigin: '*'` com dado sensível | high | `check-frontend` |
| CSP é a rede de segurança, não a defesa primária: sanitizar na fonte, CSP como camada 2 | high | `check-frontend`, `check-headers-security` |

**Princípio Rossi**: "sanitize na saída, valide na entrada, e assuma que o CSP
vai falhar". Defesa em profundidade — nunca uma camada só.

---

## 2. Trabalho Eficaz com Código Legado (Michael C. Feathers)

Foco: mudar código antigo/sem teste **sem quebrar**. É exatamente o terreno do
blindar (opera em projeto existente, muitas vezes sem cobertura).

Regras que viram comportamento de agente (fase de rounds, `04-rounds-loop`):

1. **Legacy = código sem teste.** Antes de modificar um trecho pra blindar,
   se não há teste cobrindo o comportamento atual, escreva um
   **characterization test** (teste que documenta o que o código faz HOJE,
   mesmo que "errado") antes de tocar nele. Só então mude.
2. **Ache o seam.** Um *seam* é o ponto onde dá pra alterar comportamento sem
   editar no lugar (injeção de dependência, wrapper, flag). Prefira blindar
   via seam a reescrever a função inteira — round menor, risco menor.
3. **Sprout / Wrap** em vez de editar dentro de método grande e obscuro: crie
   método/classe nova (testável) e chame do ponto mínimo. Casa com a regra
   blindar "round ≤ 80 LOC, 1 vetor".
4. **Não refatore e blinde no mesmo PR.** Feathers separa "cobrir com teste" →
   "mudar" → "refatorar". Blindar já proíbe refactor durante hardening
   (anti-padrão). Este livro é a justificativa metodológica.

> Aplicação no blindar: quando um agente vai adicionar defesa em código sem
> teste, o passo 0 é **characterization test do comportamento atual**, não a
> defesa. Isso vira o "N/A vira teste de regressão" já presente no SKILL.md,
> estendido pra "comportamento pré-existente vira teste antes de mudar".

---

## 3. Alice and Bob Learn Application Security (Kim Crawley)

Foco: mentalidade de appsec e as fraquezas mais comuns. Alimenta os agentes de
segurança e o `adversarial-reviewer`.

Checklist mental que o `adversarial-reviewer` aplica (complementa OWASP ASVS):

- **CIA**: toda mudança preserva Confidencialidade, Integridade,
  Disponibilidade? Uma defesa que derruba disponibilidade não é defesa.
- **Defense in depth**: nunca uma camada só. Se o WAF cair, o input validation
  segura? Se o input validation falhar, o parametrized query segura?
- **Least privilege**: o código/serviço tem o mínimo de permissão? Token com
  escopo amplo é finding.
- **Fail secure**: no erro, o sistema nega (não libera). `catch` que deixa
  passar é finding.
- **Não confie no cliente**: validação de front-end é UX, não segurança.
  Toda regra crítica re-valida no servidor.
- **Secrets não vivem no código nem no bundle.** Front-end `NEXT_PUBLIC_*`
  nunca carrega segredo real.

> Aplicação: `adversarial-reviewer` roda essas 6 lentes como perguntas de
> refutação. Regra blindar "refute is the safe default" já implementa o viés.

---

## 4. Construindo Sistemas Seguros e Resilientes (Leandro Silva)

Foco: segurança **na arquitetura desde o início** + resiliência a ameaça real.
Sustenta o princípio fundador `security-first` e os agentes de resiliência.

- **Segurança é fundação, não fase final.** Já é o princípio fundador do SKILL.md.
- **Resiliência = degradar, não cair.** Circuit breaker, timeout, bulkhead,
  fallback. Materializado em [`check-fallback-resilience`](../templates/checks/check-fallback-resilience.sh),
  `resilience`, `chaos-engineering`.
- **Blast radius**: toda falha tem raio de dano contido? Um serviço que cai não
  derruba os outros (isolamento). Casa com `api-surface-isolation`, `tenant-isolation-tests`.
- **Assuma o breach**: projete como se o atacante já estivesse dentro
  (segmentação, least privilege, audit log imutável). Casa com `observability`
  (hash chain no audit) e módulo 19 (pentest ativo).

---

## 5. Engenharia de sistemas de IA (Huyen, Hulten, Burkov) + OWASP LLM Top 10

Foco: arquitetar, integrar, testar e **manter** sistemas que usam IA/LLM de
forma segura. Fontes: *Designing Machine Learning Systems* (Chip Huyen),
*Building/Engineering Intelligent Systems* (Geoff Hulten), *ML Engineering*
(Andriy Burkov), *ML Design Patterns* (Lakshmanan et al.) e o
[OWASP Top 10 para Aplicações de LLM 2025](https://genai.owasp.org/).

### Cobertura OWASP LLM Top 10 no blindar (mapa)

| # | Risco | Materializado em |
|---|---|---|
| LLM01 | Prompt Injection | [`prompt-injection-defense`](../templates/checks/check-prompt-injection-defense.sh), `ai-llm-safety` |
| LLM02 | Sensitive Info Disclosure | `ai-llm-safety` (PII em prompt sem redact) |
| LLM03 | Supply Chain | `supply-chain`, `mcp-security`, `sbom-slsa` |
| LLM04 | Data/Model Poisoning | `fine-tune-data-leak` (API) |
| LLM05 | Improper Output Handling | `ai-llm-safety` (output em eval/innerHTML/SQL) |
| LLM06 | Excessive Agency | `ai-llm-safety` (tool destrutiva sem confirmação humana) |
| **LLM07** | **System Prompt Leakage** | [`llm-system-prompt-leak`](../templates/checks/check-llm-system-prompt-leak.sh) ⭐ v0.48 |
| LLM08 | Vector/Embedding Weaknesses | `vector-db-security` (API), `rag-quality` (API) |
| LLM09 | Misinformation/Overreliance | `ai-llm-safety` (aviso "pode conter erros") |
| LLM10 | Unbounded Consumption | `ai-llm-safety` (max_tokens + rate limit) |

### Arquitetura: isolar o provider (Clean Arch + Ports & Adapters)

O maior erro é acoplar o SDK do provider (`openai`, `anthropic`) direto na regra
de negócio. Se o provider muda a assinatura ou você migra pra modelo local
(Llama), o sistema inteiro quebra.

- **Domínio define um Port** (`interface AnaliseSentimentoPort`) — não sabe o que
  é token, JSON de provider, nem HTTP.
- **Infra implementa o Adapter** (`OpenAIAdapter`, `LlamaAdapter`) — traduz
  objeto de negócio ↔ formato do provider.
- **AI Gateway centralizado**: roteamento de prompts, rotação de chave, rate
  limit e rastreamento de custo num lugar só (não cada serviço chamando a IA
  caótico). Casa com `cost-observability` e `api-gateway`.

> Consultivo (não vira check determinístico por alto FP): os agentes `architect`
> e `solution-architect` recomendam esse desacoplamento quando veem SDK de
> provider importado dentro de camada de domínio.

### Qualidade sob não-determinismo (o teste da IA)

Mesmo input → saída ligeiramente diferente. Testar exige estratégia própria:

1. **Mock do adapter** pra testes de unidade da regra de negócio — substitui o
   provider por stub que retorna string previsível. Testes ficam 100%
   determinísticos. (Habilitado pelo Ports & Adapters acima.)
2. **Asserção flexível, não exata**: valide **schema** (retornou JSON com os
   campos obrigatórios?) em vez de `assert == "X"`.
3. **LLM-as-a-judge**: um modelo avaliador julga a saída por métrica
   (toxicidade, acurácia, tom) em vez de igualdade literal.
4. **Guardrails de saída**: trate a resposta da IA como **não confiável** —
   parsing robusto + validação de esquema + sanitização antes de renderizar ou
   executar (LLM05). Já materializado em `ai-llm-safety`.
5. **Monitorar data drift**: sistema de IA degrada em produção conforme os dados
   do mundo real mudam. Exige telemetria contínua + alerta (não é "funciona até
   alguém mexer no código"). Casa com `observability` e `mlops`.

---

## Livros de arquitetura e código (princípio, não check)

Clean Architecture, Fundamentals of Software Architecture, The Hard Parts,
Código Limpo, O Programador Pragmático, Refatoração — **não viram check
determinístico** (estilo/design não é grep-ável com fidelidade), mas informam
o raciocínio dos agentes `architect`, `solution-architect`, `api-design`,
`business-logic`:

- **Separar regra de negócio de ferramenta** (Clean Arch): a lógica central não
  depende de framework/DB/UI. Trocar Postgres por outro não toca no domínio.
- **Trade-off explícito** (Hard Parts / Fundamentals): toda decisão de arquitetura
  documenta o que ganha e o que perde. Não existe "melhor", existe "melhor pra
  este contexto".
- **Refatoração é passo separado e testado** (Fowler): nunca junto de mudança de
  comportamento. Reforça o anti-padrão blindar "refactor durante hardening".

Esses princípios entram no output consultivo dos agentes de arquitetura, não no
gate determinístico.
