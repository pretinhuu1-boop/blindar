---
name: feature-flags-killswitch
category: dx
module: 14
priority: P2
lead: release-lead
authority: implement
description: |
  Dá para desligar sem deploy? Flag lida em runtime (sistema dedicado, ambiente ou banco) contra constante de build. `const NOVO_CHECKOUT = true` não é flag: só muda com o mesmo deploy que você está tentando evitar.
---

# Agent: feature-flags-killswitch

Sem kill switch, a única forma de tirar do ar um recurso que quebrou é um deploy
de reversão: build, pipeline, fila de aprovação — dez a quarenta minutos com o
problema no ar. Com flag lida em runtime, é um toggle.

A distinção que importa: **`const NOVO_CHECKOUT = true` não é flag.** É constante
de build. Ela só muda com o mesmo deploy que você está tentando evitar — e é pior
que não ter flag nenhuma, porque dá a impressão de que existe um controle.

Divisão com o [`feature-flags`](feature-flags.md): lá é a disciplina de uso
(nomenclatura, ciclo de vida, remoção de flag morta). Aqui é uma pergunta só —
existe interruptor que funciona sem deploy?

## O que o check já garante

[`check-feature-flags-killswitch.sh`](../templates/checks/check-feature-flags-killswitch.sh):

| Situação | Severidade |
|---|---|
| Nenhum sistema de flag e nenhuma flag de runtime | **med** |
| Só constante de build fingindo de flag | **med** |
| Há kill switch, mas também constante hardcoded | **low** |

Aceita: Unleash, LaunchDarkly, Flagsmith, GrowthBook, ConfigCat, `@vercel/flags`,
ou leitura de `process.env.FEATURE_*` / tabela `feature_flags` em runtime.

Auto-skip em projeto sem serviço que fique no ar.

## Variável de ambiente conta — com uma ressalva

`process.env.FEATURE_X === "on"` **é** kill switch se for lido a cada requisição:
muda com um restart, sem build. Vale para a maioria dos projetos, e não exige
provedor externo.

A ressalva: em várias plataformas mudar variável de ambiente **reinicia o
processo**, o que é mais lento e mais barulhento que um toggle real. Para
recurso crítico com rollout gradual, flag em banco ou sistema dedicado responde
em segundos e permite ligar para 5% dos usuários primeiro.

Ler a variável uma vez no boot e guardar em constante anula a vantagem — vira
constante de build com passo extra.

## O ciclo de vida que evita o próximo problema

1. **Nasce desligada**, com data de remoção anotada.
2. **Rollout gradual**: 5% → 25% → 100%, com métrica de erro comparada entre os
   grupos.
3. **Kill switch testado** antes de precisar dele — desligar em produção uma vez,
   de propósito, fora do horário de pico.
4. **Morre.** Flag permanente é `if` com nome bonito: dobra os caminhos de
   execução e nunca mais é testada nos dois estados.

## O que só se prova exercitando

| Verificar | Como |
|---|---|
| O toggle **funciona** em produção | desligue de propósito e confira o comportamento |
| Quem pode desligar | plantão sem acesso ao painel não tem kill switch |
| O caminho desligado ainda funciona | o código antigo apodrece se ninguém o exercita |
| Estado da flag é observável | métrica e log precisam dizer qual caminho rodou |
