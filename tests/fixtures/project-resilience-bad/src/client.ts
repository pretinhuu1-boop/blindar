// FIXTURE VULNERAVEL — chamada externa sem timeout, sem circuit, sem retry.
export async function getUser(id: string) {
  const r = await fetch(`https://api.example.com/users/${id}`);
  return r.json();
}
