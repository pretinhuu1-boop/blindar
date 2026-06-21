import { logger } from './lib/logger';

export function add(a: number, b: number): number {
  return a + b;
}

export function greet(name: string): string {
  return `Hello, ${name}`;
}

logger.info({ event: 'app.started' });
