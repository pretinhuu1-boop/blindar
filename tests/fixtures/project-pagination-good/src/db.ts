// FIXTURE SEGURA — comentarios neutros.
import { prisma } from './client';
export function listUsers(cursor?: string) {
  return prisma.user.findMany({ take: 20, cursor: cursor ? { id: cursor } : undefined });
}
