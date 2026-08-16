---
name: seo-foundation
category: frontend
module: 10
lead: frontend-lead
authority: implement
priority: P1
description: |
  A fundação técnica que decide se o site pode ser encontrado: robots que não bloqueia renderização, sitemap só com URLs 200, canonical absoluta, host e barra final normalizados, 404 com status real e llms.txt. Complementa o seo-marketing-meta, que cuida dos metadados.
---

# Agent: seo-foundation

O site pode ser encontrado, e a autoridade dele está inteira num lugar só?

Divisão com o [`seo-marketing-meta`](seo-marketing-meta.md): lá são os
**metadados** (title, og:image, JSON-LD, noindex). Aqui é a **fundação** — o que
está por baixo e, quando errado, faz o resto não importar.

> **O erro mais caro de SEO técnico**: bloquear CSS e JS no `robots.txt` "para
> economizar crawl". O Google renderiza a página como um navegador. Sem folha de
> estilo e sem script ele vê um site quebrado — e avalia como tal.

## O que o check já garante

[`check-seo-foundation.sh`](../templates/checks/check-seo-foundation.sh) cobre o
verificável no repositório: robots bloqueando recurso de renderização
(**high**), robots sem `Sitemap:` (**med**), ausência de canonical (**high**),
de página 404 (**med**), de normalização de host/barra (**med**) e de
`llms.txt` (**low**).

## O que só se prova com o site no ar

| Verificar | Como | Por que o arquivo não basta |
|---|---|---|
| 404 devolve **404** | `curl -sI /rota-inexistente` | "soft 404" devolve **200** com página de erro — o Google indexa milhares de páginas de erro como se fossem conteúdo |
| Redirect é **301** | `curl -sI http://…` e `http://www…` | 302 não transfere autoridade; e sem redirect, `www` e não-`www` são dois sites concorrendo entre si |
| Barra final resolve | `/contato` × `/contato/` | as duas respondendo 200 são **conteúdo duplicado** |
| Compressão ativa | `curl -H "Accept-Encoding: br,gzip" -I` | Brotli/Gzip configurado no arquivo e desligado no proxy é o caso comum |
| TTFB | medir | alvo < 200–600 ms |
| Canonical **resolvida** | ver o HTML servido | canonical apontando para URL que redireciona, ou relativa, não consolida |
| Sitemap só com 200 | percorrer as URLs | é o item mais violado da lista |

**Sitemap merece atenção especial.** Ele é uma declaração: "estas são minhas
páginas boas". URL que redireciona, que devolve 404, que está `noindex` ou
bloqueada no robots **não pode estar lá** — cada uma corrói a confiança no
arquivo inteiro. Sitemap gerado automaticamente a partir de rotas costuma
incluir exatamente essas.

## `llms.txt`

Novo e ainda raro, o que o torna barato de fazer e diferenciador. Markdown
simples na raiz com o que um assistente precisa para responder sobre o negócio
sem adivinhar pelo HTML: o que a empresa faz, produtos e serviços, links da
documentação principal, FAQ, e como contratar ou entrar em contato.

O `llms-full.txt` é a versão estendida, com o conteúdo em si e não só os
ponteiros.

## Multi-idioma

Se houver mais de um idioma ou região: `hreflang` **cruzado e
autorreferencial** — cada versão aponta para todas, inclusive para si mesma —
mais `x-default`. Hreflang que aponta só num sentido é ignorado, e o erro passa
despercebido porque nada quebra visivelmente.

## Ordem de implementação

Quando falta tudo, esta ordem entrega valor mais rápido:

1. Desbloquear CSS/JS no robots — sem isso, nada mais é avaliado corretamente
2. Canonical
3. Normalização de host e barra final (301)
4. 404 com status real
5. Sitemap saneado, só com 200
6. `llms.txt`

## Anti-padrões

- ❌ Bloquear `/_next/`, `/assets/` ou `*.css` no robots.
- ❌ `noindex` esquecido em produção depois de subir de homologação — é o
  incidente de SEO mais comum, e o mais silencioso.
- ❌ Sitemap com URL que redireciona, 404 ou `noindex`.
- ❌ Soft 404: página de erro devolvendo 200.
- ❌ Canonical relativa, ou apontando para URL que redireciona.
- ❌ Servir `www` e não-`www` sem escolher um e redirecionar o outro.
- ❌ `hreflang` sem `x-default` ou sem autorreferência.
- ❌ Tratar SEO como camada de metadado. Se o crawler não renderiza a página,
  o metadado perfeito não salva.
