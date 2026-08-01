// Pseudônimo estável NÃO REVERSÍVEL, pra correlacionar sem gravar o valor.
//
// HMAC com chave secreta, JAMAIS hash puro: SHA-256 de um CPF é força-bruta de
// segundos (espaço pequeno e conhecido). O mesmo vale, com folga, pra IPv4 —
// são 2^32 endereços, enumeráveis integralmente. Hash sem segredo não anonimiza.

import { createHmac } from 'node:crypto';

export function pseudonym(value, key, prefix = 'u_') {
  if (value == null || value === '') return null;
  if (!key) throw new Error('pseudonym: chave ausente — não degrade pra hash puro');
  return prefix + createHmac('sha256', key).update(String(value)).digest('hex').slice(0, 16);
}

// Salt do IP roda a cada 24 h: dentro do dia "é o mesmo ator?" continua
// respondível; a ligação entre dias morre com o salt.
export function ipSalt(key, day) {
  return createHmac('sha256', key).update(`ip-salt:${day}`).digest();
}

// Rede grosseira: /24 em IPv4, /48 em IPv6. Responde "qual provedor?" sem
// guardar o endereço. Combinada com ASN, cobre investigação de abuso.
export function ipNet(ip) {
  if (typeof ip !== 'string' || !ip) return null;
  if (ip.includes(':')) {
    const parts = ip.split(':');
    return parts.slice(0, 3).join(':') + '::/48';
  }
  const o = ip.split('.');
  if (o.length !== 4) return null;
  return `${o[0]}.${o[1]}.${o[2]}.0/24`;
}

export function ipFields(ip, key, day) {
  if (!ip) return {};
  return {
    ip_hash: pseudonym(ip, ipSalt(key, day), 'ip_'),
    ip_net: ipNet(ip),
  };
}
