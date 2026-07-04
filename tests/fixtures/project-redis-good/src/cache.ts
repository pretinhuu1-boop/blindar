// FIXTURE SEGURA — comentarios neutros.
import Redis from 'ioredis';
const redis = new Redis({ password: process.env.REDIS_PASSWORD });
export const put = (k: string, v: string) => redis.setex(k, 60, v);
