// FIXTURE SEGURA — chave PIX via env, handler /pix com audit log.
export const pixKey = process.env.PIX_KEY;
export function handleDevolucao(txid: string) {
  // rota /pix/devolucao registra auditLog (BACEN 4658, 5 anos)
  auditLog.create({ txid });
}
declare const auditLog: { create: (x: unknown) => void };
