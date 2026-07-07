import { ConfigService } from '@nestjs/config';
import { Queue } from 'bullmq';

import { parseRedisUrl } from '../../common/redis/parse-redis-url';

/** DI token cho BullMQ Queue `ai-review` (spec FR-S3-3, Event Changes). */
export const REVIEW_QUEUE = Symbol('REVIEW_QUEUE');

export interface ReviewJobPayload {
  analysisId: string;
}

/**
 * Re-export — implementation chuyển vào `common/redis/parse-redis-url.ts`
 * (dùng chung với `common/rate-limit`, FR-S4-4) để tránh `common` import
 * ngược từ `modules`. Giữ export ở đây để không phá import hiện có
 * (`analysis.worker.ts`, `token-cleanup.job.ts`).
 */
export { parseRedisUrl };

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
