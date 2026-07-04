// FIXTURE SEGURA — envelope encryption DEK/KEK (AES-256-GCM).
const ALG = 'aes-256-gcm';
export function generateDek() { return ALG; }
export function encryptField(v: string) { return v; }
export function unwrapDek(dek: string) { return dek; }
export function phoneSearchHash(phone: string) { return phone; }
