// FIXTURE VULNERAVEL — comentarios neutros.
import { prisma } from './client';
export function raw(sql: string) {
  return prisma.$queryRawUnsafe(sql);
}
