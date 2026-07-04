// FIXTURE VULNERAVEL — comentarios neutros.
export function charge(req: any) {
  const cvv = req.body.cvv;
  return process(cvv);
}
declare function process(x: string): void;
