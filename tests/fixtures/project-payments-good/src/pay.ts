// FIXTURE SEGURA — tokenizacao, nada de dado sensivel armazenado.
export function charge(req: any) {
  const paymentToken = req.body.paymentToken;
  return stripeCharge(paymentToken);
}
declare function stripeCharge(token: string): void;
