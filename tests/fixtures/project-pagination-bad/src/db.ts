// FIXTURE VULNERAVEL — comentarios neutros.
import { prisma } from './client';
export function listUsers() {
  return prisma.user.findMany({ where: { active: true } });
}
