---
name: a11y-executado
category: frontend
module: 10
priority: P1
lead: frontend-lead
authority: implement
description: |
  Acessibilidade MEDIDA, não recomendada: axe-core contra a página no ar quando há URL, e razão de contraste calculada a partir do CSS sempre. Torna executável o que o responsive-a11y cobre como heurística de grep.
---

# Agent: a11y-executado

O [`responsive-a11y`](responsive-a11y.md) é playbook com heurística de grep: acha
`<img>` sem `alt` e `outline: none`. Útil, e insuficiente — ele não sabe se o
contraste passa, se o foco é visível, se o campo tem rótulo associado de verdade.

Nenhuma dessas coisas é opinião. **WCAG 2.2 AA define número**, e número se
calcula.

## Duas camadas, e a segunda diz quando não rodou

**EXECUTADA — axe-core contra a página no ar** (`--url=` ou `BLINDAR_TARGET_URL`,
com `@axe-core/cli` instalado). Violação `critical`/`serious` vira **high**,
`moderate` vira **med**, `minor` vira **low**, cada uma com a regra e o seletor
do elemento.

**MEDIDA — razão de contraste calculada a partir do CSS do repositório.**
Aritmética de luminância relativa (WCAG 2.x §1.4.3) sobre o par
`color`/`background` declarado na mesma regra. Abaixo de 4.5:1 → **med**, com o
número no achado.

O escopo da segunda camada é **deliberadamente estreito, e o check diz isso**: cor
herdada de outra regra, vinda de variável CSS ou aplicada em runtime não entra na
conta. É pouco, e é honesto — melhor um número verdadeiro sobre parte da folha
que uma opinião sobre o todo.

Se nenhuma das duas rodou, o resultado é `skipped` com `missing_tool`.
**Acessibilidade não verificada não é acessibilidade aprovada.**

## Auto-skip

Projeto sem interface. Auto-skip com motivo, nunca aprovação silenciosa.

## O que o axe pega e o grep nunca pegaria

- **Nome acessível** de botão só com ícone — o leitor de tela anuncia "botão".
- **Rótulo associado** ao campo (`for`/`id`), não só um texto perto dele.
- **ARIA inválido**: `role` que não aceita o atributo usado, `aria-labelledby`
  apontando para id inexistente.
- **Ordem de cabeçalhos** e landmarks.
- **Contraste computado** com a cascata inteira aplicada — inclusive tema escuro.

## O que nem o axe pega

Ferramenta automatizada cobre cerca de um terço dos critérios WCAG. O resto exige
uso:

| Verificar | Como |
|---|---|
| Navegação só por teclado | `Tab` do começo ao fim; alcança tudo? o foco é visível? |
| Armadilha de foco em modal | abre, fecha com `Esc`, e devolve o foco de onde veio |
| Ordem de leitura faz sentido | leitor de tela real (NVDA, VoiceOver) numa tarefa completa |
| Alvo de toque ≥ 44×44px | no aparelho, não no DevTools |
| O `alt` **diz** alguma coisa | `alt="imagem"` passa no automático e não ajuda ninguém |
