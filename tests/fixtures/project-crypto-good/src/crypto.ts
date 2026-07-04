// FIXTURE SEGURA — comentarios neutros.
import crypto from 'crypto';
import bcrypt from 'bcrypt';
export async function hashPassword(password: string) {
  return bcrypt.hash(password, 12);
}
export function newToken() {
  return crypto.randomBytes(32).toString('hex');
}
