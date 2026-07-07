import { Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import Redis from 'ioredis';

import { parseRedisUrl } from '../redis/parse-redis-url';

/** DI token cho client `ioredis` dùng riêng cho rate limiting (FR-S4-4). */
export const RATE_LIMIT_REDIS = Symbol('RATE_LIMIT_REDIS');

const logger = new Logger('RateLimitRedis');

/**
 * Provider factory — tạo 1 `ioredis` instance riêng cho rate-limit counters
 * (tách khỏi connection BullMQ dùng object nested khác — xem comment trong
 * `review.queue.ts`). Lazy connect, không throw ở constructor: lệnh Redis lỗi
 * (down/timeout) được `RateLimitService` bắt và fail-open (EC-S4-1) — client
 * tự retry reconnect ở background, không cần fail app boot vì Redis tạm chết.
 */
export const rateLimitRedisProvider = {
  provide: RATE_LIMIT_REDIS,
  useFactory: (config: ConfigService): Redis => {
    const redisUrl = config.get<string>('REDIS_URL') ?? 'redis://localhost:6379';
    const client = new Redis({
      ...parseRedisUrl(redisUrl),
      lazyConnect: false,
      maxRetriesPerRequest: 1,
      retryStrategy: (times: number) => Math.min(times * 200, 2000),
    });
    client.on('error', (err) => {
      // EC-S4-1: log ERROR khi Redis không kết nối được — RateLimitService
      // vẫn fail-open cho traffic authenticated, global IP limit là lưới cuối.
      logger.error(`Redis rate-limit connection error: ${err.message}`);
    });
    return client;
  },
  inject: [ConfigService],
};
