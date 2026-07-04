// FIXTURE SEGURA — comentarios neutros.
export async function pay(req: any) {
  const itemId = req.body.itemId;
  const amount = await priceOf(itemId);
  return charge(amount);
}
declare function priceOf(id: string): Promise<number>;
declare function charge(a: number): void;
