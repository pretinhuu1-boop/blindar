// FIXTURE VULNERAVEL — comentarios neutros.
export function pay(req: any) {
  const amount = req.body.amount;
  return charge(amount);
}
declare function charge(a: number): void;
