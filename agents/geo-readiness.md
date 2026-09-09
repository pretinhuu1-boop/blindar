---
name: geo-readiness
category: frontend
module: 10
priority: P2
lead: frontend-lead
authority: implement
description: |
  GEO — Generative Engine Optimization. Gate CONDICIONAL de prontidão para ser citado por ChatGPT, Perplexity, AI Overviews e Claude: JSON-LD, política intencional de crawler de IA em dois tiers, conteúdo visível sem JS, resposta extraível e sinais de E-E-A-T. Auto-skip é a regra — a maioria dos projetos não tem superfície pública de conteúdo.
---

# Agent: geo-readiness

**GEO não é SEO com outro nome.** SEO clássico disputa POSIÇÃO numa lista de dez
links azuis. GEO disputa ser **citado dentro de uma resposta** que o usuário lê
sem clicar em nada.

São mecânicas diferentes. O motor generativo não ranqueia a sua página: ele
extrai um fato dela e credita a fonte. O que decide não é backlink nem densidade
de palavra-chave — é o fato estar declarado de forma extraível, no HTML do
servidor, com identidade e data.

Divisão com os vizinhos:

| Agente | Cuida de |
|---|---|
| [`seo-marketing-meta`](seo-marketing-meta.md) | metadados: title, og:image, canonical, noindex |
| [`seo-foundation`](seo-foundation.md) | fundação: robots, sitemap, 404 real, normalização de host |
| `searchfit-seo:ai-visibility` (skill) | **advisory** de conteúdo: o que escrever |
| **geo-readiness** | **gate executado** de prontidão: o que o motor consegue extrair |

## Auto-skip é a regra, não a exceção

A maioria dos projetos que o blindar audita **não tem** superfície pública de
conteúdo. API, CLI, backend de bot e painel interno não têm o que ser citado —
cobrar GEO deles é ruído.

O check só roda com sinal positivo de conteúdo público: SSG de conteúdo (Astro,
Hugo, Docusaurus, VitePress, Jekyll, Gatsby), diretório com dois ou mais artigos
em markdown, ou landing com `meta description` e prosa de verdade. Sem isso →
`skipped` com o motivo escrito.

## O que o check já garante

[`check-geo-readiness.sh`](../templates/checks/check-geo-readiness.sh):

| Dimensão | Achado | Severidade |
|---|---|---|
| Dados estruturados | zero JSON-LD em página de conteúdo | **high** |
| Crawler de IA | tier RESPOSTA bloqueado no robots | **high** |
| Crawler de IA | nenhuma política de IA declarada | **med** |
| Crawler de IA | sem `llms.txt` | **low** |
| Renderização | HTML servido vazio (só contêiner + script) | **high** |
| Renderização | framework de cliente sem SSR/SSG | **med** |
| Extração | sem bloco respondível (FAQ, "o que é", FAQPage) | **med** |
| E-E-A-T | sem data, autoria, canonical ou Open Graph | **med** |

## Os dois tiers de crawler de IA

O check **não exige "libere todos"**. Bloquear crawler de treino é decisão
legítima do operador — licenciamento, banda, política editorial. O que ele separa
é o que tem consequência diferente.

**Tier RESPOSTA — geram citação e tráfego. Bloqueio aqui é falha (high):**

`GPTBot`, `OAI-SearchBot`, `ChatGPT-User` (OpenAI) · `Google-Extended` e
`Googlebot` (AI Overviews / Gemini) · `ClaudeBot`, `Claude-SearchBot`,
`Claude-User`, `anthropic-ai` (Anthropic) · `PerplexityBot`, `Perplexity-User` ·
`bingbot` (o Copilot usa o índice do Bing) · `Meta-ExternalAgent`.

Bloquear estes é auto-de-indexação dos motores generativos, e quase sempre é
acidente de copiar-e-colar de um `robots.txt` alheio, não decisão.

**Tier TREINO/MENOR — muitos bloqueiam de propósito. Informativo, nunca falha
sozinho:**

`CCBot` (Common Crawl) · `Bytespider` (ByteDance) · `Amazonbot` ·
`Applebot-Extended` · `cohere-ai` e `cohere-training-data-crawler` ·
`MistralAI-User` · `YouBot` · `DuckAssistBot` · `Diffbot` · `AI2Bot` ·
`PetalBot` · `omgili` / `omgilibot`.

A postura destes é **reportada como observação**. Só vira aviso quando a política
é inconsistente — parte da lista bloqueada sem critério aparente.

> **O roster tem data.** Está marcado no próprio check como
> `revisar trimestralmente, últ.: 2026-09`. User-agent de IA muda toda hora, e
> lista fixa sem data envelhece calada. **User-agent fora do roster não vira
> "aprovado" automático** — vira "não classificado, verifique manualmente".

## Por que o HTML do servidor importa mais aqui que no SEO

O Googlebot renderiza JavaScript (com atraso e com custo). **Boa parte dos
crawlers de IA não renderiza.** Eles baixam o HTML, extraem o texto e vão embora.

Conteúdo montado no cliente, para eles, simplesmente não existe. Uma SPA pode
ranquear razoavelmente no Google e ser **invisível** para ChatGPT e Perplexity ao
mesmo tempo — e ninguém percebe, porque não há relatório de "não fui citado".

## O que torna uma frase citável

Motor generativo cita **afirmação auto-contida com um fato dentro**:

- ❌ "A melhor solução do mercado para o seu negócio crescer."
- ✅ "O prazo de devolução é de 30 dias corridos a partir do recebimento."

A segunda pode ser extraída, atribuída e verificada. A primeira não diz nada que
alguém possa repetir. Slogan não é resposta.

## O que só se prova fora do repositório

| Verificar | Como |
|---|---|
| Você **é** citado | pergunte ao ChatGPT/Perplexity algo que sua página responde |
| O JSON-LD valida | Rich Results Test / validator.schema.org |
| O `robots.txt` servido é o do repositório | CDN e proxy servem outro com frequência |
| O HTML cru tem o conteúdo | `curl -s url \| sed 's/<[^>]*>//g'` — o que sobra é o que o crawler vê |
| A data é a data real | `dateModified` que nunca muda vira sinal negativo |
