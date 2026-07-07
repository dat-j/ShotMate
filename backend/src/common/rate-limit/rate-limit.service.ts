import { Inject, Injectable, Logger } from '@nestjs/common';
import type Redis from 'ioredis';

import { RATE_LIMIT_REDIS } from './redis-client.provider';

export interface RateLimitCheck {
  /** Redis key duy nhất cho counter (đã bao gồm scope + identity). */
  key: string;
  /** Số request tối đa trong `windowSeconds`. */
  limit: number;
  windowSeconds: number;
}

export interface RateLimitResult {
  /** false khi vượt giới hạn — caller phải trả 429. */
  allowed: boolean;
  /** true khi Redis lỗi và ta fail-open (EC-S4-1) — không tính là "chặn". */
  failedOpen: boolean;
}

/**
 * RateLimitService — counter kiểu INCR + EXPIRE trên Redis riêng cho rate
 * limiting (FR-S4-4). Redis chết → fail-open cho traffic authenticated
 * (EC-S4-1): không chặn user vì lỗi hạ tầng, nhưng log ERROR để alert.
 * Global IP limit (`@fastify/rate-limit`, in-memory) vẫn là lưới cuối trong
 * main.ts — không phụ thuộc service này.
 */
@Injectable()
export class RateLimitService {
  private readonly logger = new Logger(RateLimitService.name);

  constructor(@Inject(RATE_LIMIT_REDIS) private readonly redis: Redis) {}

  /**
   * Kiểm tra + tăng counter cho 1 key. Dùng `INCR` rồi `EXPIRE` chỉ ở lần
   * đầu (ttl == -1 nghĩa là key mới tạo, chưa có TTL) — tránh reset window
   * liên tục mỗi request (sliding-window giả bằng fixed-window là đủ theo
   * spec, đơn giản và dễ test).
   */
  async check({ key, limit, windowSeconds }: RateLimitCheck): Promise<RateLimitResult> {
    try {
      const count = await this.redis.incr(key);
      if (count === 1) {
        await this.redis.expire(key, windowSeconds);
      }
      return { allowed: count <= limit, failedOpen: false };
    } catch (err) {
      this.logger.error(
        `Redis rate-limit check failed for key="${key}" — fail-open (EC-S4-1): ${
          err instanceof Error ? err.message : String(err)
        }`,
      );
      return { allowed: true, failedOpen: true };
    }
  }
}
