// FIXTURE VULNERAVEL — dados de paciente sem envelope encryption.
export function createPatient(name: string, phone: string) {
  return db.patients.create({ name, phone });
}
declare const db: any;
