// FIXTURE SEGURA — merge recursivo com guard de chaves perigosas.
const DANGEROUS = ['__proto__', 'constructor', 'prototype'];

function deepMerge(target, source) {
  for (const key of Object.keys(source)) {
    if (DANGEROUS.includes(key)) continue; // bloqueia prototype pollution
    if (typeof source[key] === 'object' && source[key] !== null) {
      target[key] = deepMerge(target[key] || Object.create(null), source[key]);
    } else {
      target[key] = source[key];
    }
  }
  return target;
}

module.exports = { deepMerge };
