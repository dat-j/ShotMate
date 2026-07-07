import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { APP_GUARD } from '@nestjs/core';

import { JwtAuthGuard } from './common/auth/jwt-auth.guard';
import { AppJwtModule } from './common/auth/jwt.module';
import { validateEnv } from './common/config/env.validation';
import { LoggerModule } from './common/logging/logger.module';
import { PrismaModule } from './common/prisma/prisma.module';
import { RateLimitGuard } from './common/rate-limit/rate-limit.guard';
import { RateLimitModule } from './common/rate-limit/rate-limit.module';
import { AiReviewModule } from './modules/ai-review/ai-review.module';
import { AnalysisModule } from './modules/analysis/analysis.module';
import { AuthModule } from './modules/auth/auth.module';
import { CreditsModule } from './modules/credits/credits.module';
import { FeedbackModule } from './modules/feedback/feedback.module';
import { HealthModule } from './modules/health/health.module';
import { PhotosModule } from './modules/photos/photos.module';
import { SubscriptionsModule } from './modules/subscriptions/subscriptions.module';
import { SyncModule } from './modules/sync/sync.module';
import { UsersModule } from './modules/users/users.module';

@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true, validate: validateEnv }),
    LoggerModule,
    PrismaModule,
    RateLimitModule,
    AppJwtModule,
    HealthModule,
    AuthModule,
    UsersModule,
    PhotosModule,
    AnalysisModule,
    AiReviewModule,
    CreditsModule,
    SubscriptionsModule,
    SyncModule,
    FeedbackModule,
  ],
  providers: [
    // JWT guard global — route @Public() bỏ qua (spec FR-S3-1). Thứ tự
    // provider = thứ tự chạy guard trong Nest: JwtAuthGuard trước để
    // req.user sẵn sàng cho RateLimitGuard (default 60/phút/user, FR-S4-4).
    { provide: APP_GUARD, useClass: JwtAuthGuard },
    { provide: APP_GUARD, useClass: RateLimitGuard },
  ],
})
export class AppModule {}
