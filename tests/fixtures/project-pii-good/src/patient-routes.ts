// FIXTURE SEGURA — rota de paciente cifra PII antes de gravar.
import { encryptField, generateDek } from './crypto';
export function createPatient(name: string) {
  const dek = generateDek();
  return encryptField(name);
}
