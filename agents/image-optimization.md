---
name: image-optimization
category: frontend
module: 10
priority: P2
lead: frontend-lead
authority: implement
description: |
  Imagem é quase sempre o maior byte da página. Três defeitos independentes e medíveis no markup: formato legado (JPEG/PNG sem WebP/AVIF), ausência de srcset, e falta de dimensão explícita — que é CLS. Auto-skip sem imagens.
---

# Agent: image-optimization

Três defeitos independentes, todos comuns, todos medíveis no HTML.

**FORMATO.** JPEG e PNG onde WebP ou AVIF entregam a mesma imagem com 25–50% dos
bytes. Não é micro-otimização: numa landing com seis fotos é a diferença entre
2MB e 700KB.

**TAMANHO.** Sem `srcset`, o celular baixa a versão de desktop e a reduz na tela —
paga a banda inteira para exibir um terço.

**DIMENSÃO.** Sem `width`/`height` (ou `aspect-ratio`), o navegador não reserva
espaço: a imagem chega, empurra o conteúdo para baixo, e o dedo que estava indo
para um botão acerta outro. É CLS, e é o único dos Core Web Vitals que o usuário
sente diretamente como "esse site é ruim".

## O que o check já garante

[`check-image-optimization.sh`](../templates/checks/check-image-optimization.sh):

| Defeito | Severidade |
|---|---|
| `<img>` sem `width`/`height` nem `aspect-ratio` | **med** |
| `<img>` sem `srcset`/`sizes` | **low** |
| JPEG/PNG sem alternativa WebP/AVIF | **low** |

A dimensão é **med** e as outras são **low** de propósito: as duas primeiras
custam banda; a terceira custa cliques errados.

Projeto que usa `next/image`, `<NuxtImg>`, `astro:assets`, `gatsby-plugin-image`
ou `@unpic` tem os três resolvidos pelo componente — o check registra isso e
avalia só as `<img>` cruas que sobraram.

Auto-skip em projeto que não serve imagem em markup.

## O jeito curto de resolver os três

```html
<picture>
  <source srcset="/foto.avif 1x, /foto@2x.avif 2x" type="image/avif">
  <source srcset="/foto.webp 1x, /foto@2x.webp 2x" type="image/webp">
  <img src="/foto.jpg" width="1200" height="480" sizes="100vw"
       loading="lazy" decoding="async" alt="descrição real">
</picture>
```

`width`/`height` são os do **arquivo**, não os da tela — servem para o navegador
calcular a proporção. O CSS continua mandando no tamanho exibido.

`loading="lazy"` em tudo **menos** na imagem que aparece na primeira dobra: ali
ele atrasa o LCP em vez de melhorar.

## O que só se prova com o site no ar

| Verificar | Por quê |
|---|---|
| O peso real do arquivo servido | `srcset` correto apontando para JPEG de 4MB não resolve nada |
| CDN negocia formato por `Accept` | é a alternativa ao `<picture>`, e falha silenciosa |
| CLS medido | a conta real vem do campo, não do markup |
| Imagem do LCP não está `lazy` | atraso de LCP por lazy é o erro mais comum da correção |
