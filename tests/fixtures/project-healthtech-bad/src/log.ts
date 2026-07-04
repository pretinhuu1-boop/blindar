// FIXTURE VULNERAVEL — prontuario com PHI em log.
export function registrar(data: { diagnosis: string }) {
  console.log("diagnosis", data.diagnosis);
}
