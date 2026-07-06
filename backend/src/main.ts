import rateLimit from '@fastify/rate-limit';
import { ValidationPipe } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import {
  FastifyAdapter,
  NestFastifyApplication,
} from '@nestjs/platform-fastify';

import { AppModule } from './app.module';
import { HttpErrorFilter } from './common/http/http-error.filter';

async function bootstrap(): Promise<void> {
  const app = await NestFactory.create<NestFastifyApplication>(
    AppModule,
    // Body limit 1MB — ảnh KHÔNG đi qua API (chỉ signed URL); chặn payload lớn.
    new FastifyAdapter({ bodyLimit: 1024 * 1024 }),
  );

  app.setGlobalPrefix('api/v1');

  // Rate limit theo IP (tầng ngoài Cloud Armor). Per-user/per-email limit
  // enforce trong từng route (spec Rule 8).
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
