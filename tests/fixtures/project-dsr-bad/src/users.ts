export async function desativar(id: string) {
  return db.user.update({ where: { id }, data: { deletedAt: new Date() } });
}
