---
name: frontend-perf-budget
category: performance
module: 10
priority: P1
lead: frontend-lead
authority: implement
description: |
  Orçamento de performance EXECUTADO: bytes gzipped por página e por bundle, medidos e comparados a um teto configurável, mais Lighthouse (LCP/TBT/CLS) contra URL real quando disponível. Complementa o frontend-performance, que é o playbook de técnica.
---

# Agent: frontend-perf-budget

"Otimizar o front" é conselho; não é medida. **Orçamento é medida**: um número
por página, comparado a cada rodada, que estoura ou não estoura.

Sem ele, o peso cresce da forma como sempre cresce: ninguém adiciona 300KB de uma
vez, cada pessoa adiciona 20KB, e o total ninguém olha. Um ano depois a página
tem 638KB e a discussão vira "por que o painel está lento?" — pergunta sem
resposta porque não há série histórica.

Divisão com o [`frontend-performance`](frontend-performance.md): lá são as
técnicas (code splitting, RSC, `next/image`, `use client`). Aqui é o número.

## O que o check já garante

[`check-frontend-perf-budget.sh`](../templates/checks/check-frontend-perf-budget.sh)
tem duas camadas, e a segunda diz quando não rodou.

**Estática — sempre roda, sem rede e sem navegador:**

| Medida | Teto default | Severidade |
|---|---|---|
| Documento HTML servido (gzip) | 400 KB | **med** acima, **high** acima do dobro |
| JS total por diretório de build (gzip) | 400 KB | **med** acima, **high** acima do dobro |
| Tags `<script>` por página | 25 | **low** |

**Dinâmica — Lighthouse contra URL real** (`--url=` ou `BLINDAR_TARGET_URL`):

| Métrica | SLO | **med** | **high** |
|---|---|---|---|
| LCP | 2500 ms | acima | acima de 4000 ms |
| TBT | 200 ms | acima | acima de 600 ms |
| CLS | 0.1 | acima | acima de 0.25 |

Sem `lighthouse` instalado ou sem URL, o check **cai para a camada estática e
avisa**, com `missing_tool` preenchido. Sem gzip disponível, mede bytes crus e
registra que a unidade mudou. Sem nenhum artefato mensurável (build não rodado),
sai `skipped` — nada medido não é aprovação.

## Ajustar o orçamento

O teto certo é do produto, não do check. Landing de marketing e painel interno
não têm o mesmo orçamento.

```json
{ "blindar": { "perfBudgetPageKb": 250, "perfBudgetJsKb": 180 } }
```

Ou por ambiente: `BLINDAR_PERF_PAGE_KB=250 BLINDAR_PERF_JS_KB=180`.

Apertar o teto é o uso normal; **afrouxar para o CI passar é o anti-padrão** —
nesse momento o orçamento deixa de medir e passa a registrar a derrota.

## O que só se prova com o site no ar

| Verificar | Por que o byte no disco não basta |
|---|---|
| Compressão ativa no proxy | Brotli configurado no build e desligado no nginx é o caso comum |
| Cache de asset com hash | sem hash, cada deploy invalida tudo e o retorno paga de novo |
| Rede real (4G, latência alta) | o gargalo raramente é banda: é ida-e-volta |
| Thread principal sob carga | TBT medido em máquina de dev subestima o celular do cliente |
