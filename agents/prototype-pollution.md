---
name: prototype-pollution
category: security
module: 2
priority: P1
description: |
  Detecta prototype pollution em JS/TS — escrita em __proto__/constructor.
  prototype e merge recursivo caseiro que não bloqueia chaves perigosas.
  Vetor que já causou CVEs de alto impacto (lodash, minimist, jQuery).
---

# Agent: prototype-pollution

## Missão

Impedir que um atacante injete propriedades no `Object.prototype` global via
chaves controladas (`__proto__`, `constructor`, `prototype`). Uma vez poluído,
o protótipo afeta TODO objeto do processo — leva a bypass de auth, DoS, e às
vezes RCE. Fonte: [`docs/book-insights.md`](../docs/book-insights.md) § Rossi/Crawley.

## Quando rodar

- Módulo 2 (segurança core) — projetos JS/TS
- Complementa `check-security` (que cobre eval/innerHTML/open-redirect servidor)

## O que dispara finding

| Padrão | Severidade | Por quê |
|---|---|---|
| `obj["__proto__"] = ...`, `obj.__proto__ = ...` | high | Escrita direta no protótipo |
| `x.constructor["prototype"] = ...` | high | Caminho alternativo pro protótipo |
| Merge/`deepMerge` recursivo por chave dinâmica **sem** guard de `__proto__`/`constructor`/`prototype` | high | Sink clássico (padrão lodash CVE-2019-10744) |
| `Object.assign({}, JSON.parse(req.body))` | med | Chaves do usuário direto no objeto |

## Como blindar (o que o código deveria ter)

```js
// 1. Guard explícito no merge
const DANGEROUS = ['__proto__', 'constructor', 'prototype'];
function safeMerge(target, source) {
  for (const key of Object.keys(source)) {
    if (DANGEROUS.includes(key)) continue;        // bloqueia
    if (isObject(source[key])) safeMerge(target[key] ??= {}, source[key]);
    else target[key] = source[key];
  }
  return target;
}

// 2. Mapa sem protótipo pra dados do usuário
const bag = Object.create(null);                  // sem __proto__
bag[userKey] = userVal;                           // seguro

// 3. Validar com schema (zod/joi) antes de merge — só chaves conhecidas passam
```

## Falso positivo — como suprimir

- `Object.create(null)`, `hasOwnProperty.call`, e uso de `@blindar:keep` já são
  ignorados pelo check.
- Merge de lib validada (lodash ≥ 4.17.12) que já corrige internamente: declare
  em `.blindar/intelligence.yml` seção `prototype-pollution: ignore_paths`.

## Intelligence

Respeita `.blindar/intelligence.yml` via `load_intelligence_globs`. Use pra
excluir utilitários de merge de terceiros já auditados.
