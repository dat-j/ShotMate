import { ConfigService } from '@nestjs/config';
import { Queue } from 'bullmq';

/** DI token cho BullMQ Queue `ai-review` (spec FR-S3-3, Event Changes). */
export const REVIEW_QUEUE = Symbol('REVIEW_QUEUE');

export interface ReviewJobPayload {
  analysisId: string;
}

/**
 * Parse `redis://[:password@]host[:port][/db]` thành options object thay vì
 * dùng chuỗi `url` thẳng — bullmq bundle riêng một bản `ioredis` nested nên
 * truyền instance `IORedis` từ package top-level gây lỗi type identity
 * mismatch dù runtime tương thích. Object options (plain interface) tránh
 * vấn đề này hoàn toàn.
 */
export function parseRedisUrl(url: string): { host: string; port: number; password?: string; db?: number } {
  const parsed = new URL(url);
  const db = parsed.pathname && parsed.pathname !== '/' ? Number(parsed.pathname.slice(1)) : undefined;
  return {
    host: parsed.hostname || 'localhost',
    port: parsed.port ? Number(parsed.port) : 6379,
    ...(parsed.password ? { password: parsed.password } : {}),
    ...(db !== undefined && !Number.isNaN(db) ? { db } : {}),
  };
}

/**
 * Provider factory — BullMQ `Queue` lazy-connects to Redis (no network call
 * happens at construction time), so importing AnalysisModule in tests never
 * requires a live Redis instance (spec constraint: "Do NOT connect to
 * Redis/DB in constructors").
 */
export const reviewQueueProvider = {
  provide: REVIEW_QUEUE,
  useFactory: (config: ConfigService): Queue<ReviewJobPayload> => {
    const redisUrl = config.get<string>('REDIS_URL') ?? 'redis://localhost:6379';
    return new Queue<ReviewJobPayload>('ai-review', {
      connection: { ...parseRedisUrl(redisUrl), maxRetriesPerRequest: null },
    });
  },
  inject: [ConfigService],
};
