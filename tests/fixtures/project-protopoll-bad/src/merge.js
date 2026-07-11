// FIXTURE VULNERAVEL — merge recursivo sem guard de chave perigosa.
// Padrao classico de prototype pollution (estilo CVE-2019-10744).
function deepMerge(target, source) {
  for (const key in source) {
    if (typeof source[key] === 'object' && source[key] !== null) {
      target[key] = deepMerge(target[key] || {}, source[key]);
    } else {
      target[key] = source[key];
    }
  }
  return target;
}

module.exports = { deepMerge };
