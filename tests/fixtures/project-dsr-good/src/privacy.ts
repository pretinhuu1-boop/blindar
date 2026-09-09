// LGPD art. 18: acesso e eliminacao pelo proprio titular.
export async function exportUserData(id: string) {
  const u = await db.user.findUnique({ where: { id } });
  return { formato: "json", dados: u };
}

export async function eraseUserData(id: string) {
  await db.audit.deleteMany({ where: { userId: id } });
  return db.user.update({ where: { id }, data: { email: anonymize(id), cpf: null } });
}
