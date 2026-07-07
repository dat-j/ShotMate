import helmet from '@fastify/helmet';
import rateLimit from '@fastify/rate-limit';
import { ValidationPipe } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import {
  FastifyAdapter,
  NestFastifyApplication,
} from '@nestjs/platform-fastify';
import { Logger as PinoLogger } from 'nestjs-pino';

import { AppModule } from './app.module';
import { HttpErrorFilter } from './common/http/http-error.filter';

async function bootstrap(): Promise<void> {
  const app = await NestFactory.create<NestFastifyApplication>(
    AppModule,
    // Body limit 1MB — ảnh KHÔNG đi qua API (chỉ signed URL); chặn payload lớn.
    new FastifyAdapter({ bodyLimit: 1024 * 1024 }),
    // Buffer log trước khi Nest logger sẵn sàng — tránh mất log bootstrap.
    { bufferLogs: true },
  );

  // pino structured JSON logger (spec FR-S4-6) — thay Nest logger mặc định
  // ở tầng framework/bootstrap. Logger service-layer (`new Logger(...)`
  // trong auth.service.ts, analysis.service.ts...) không đổi.
  app.useLogger(app.get(PinoLogger));

  app.setGlobalPrefix('api/v1');

  // HTTP security headers (finding M1 review Sprint 3).
  await app.register(helmet as never);

  // Rate limit theo IP, in-memory per-instance (tầng ngoài Cloud Armor).
  // KHÔNG phụ thuộc Redis — đây là lưới cuối khi Redis chết (EC-S4-1).
  // Per-user/per-email limit (Redis-backed) enforce qua RateLimitGuard
  // (spec FR-S4-4, common/rate-limit/).
  await app.register(rateLimit as never, {
    max: 300,
    timeWindow: '1 minute',
  });

  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true,
      // Lỗi validate DTO → 422 VALIDATION_FAILED (spec API table: upload-url,
      // sync...). Các lỗi 400 khác (BATCH_TOO_LARGE, magic-link email) là
      // AppError explicit, không đi qua pipe này.
      errorHttpStatusCode: 422,
    }),
  );
  app.useGlobalFilters(new HttpErrorFilter());
  // JwtAuthGuard đăng ký qua APP_GUARD trong AppModule (DI đầy đủ).

  await app.listen(Number(process.env.PORT ?? 8080), '0.0.0.0');
}

void bootstrap();
