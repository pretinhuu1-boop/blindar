// FIXTURE VULNERAVEL — comentarios neutros.
import crypto from 'crypto';
export function hashPassword(password: string) {
  return crypto.createHash('md5').update(password).digest('hex');
}
