import { Global, Module } from '@nestjs/common';

import { rateLimitRedisProvider } from './redis-client.provider';
import { RateLimitGuard } from './rate-limit.guard';
import { RateLimitService } from './rate-limit.service';

/**
 * RateLimitModule — Redis-backed rate limiting (FR-S4-4, trả nợ D1). Global
 * để `RateLimitGuard` đăng ký qua `APP_GUARD` trong AppModule và mọi
 * controller dùng `@RateLimit()` không cần import lại module này.
 */
@Global()
@Module({
  providers: [rateLimitRedisProvider, RateLimitService, RateLimitGuard],
  exports: [RateLimitService, RateLimitGuard],
})
export class RateLimitModule {}
