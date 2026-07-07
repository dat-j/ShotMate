import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';

import { validateEnv } from './common/config/env.validation';
import { PrismaModule } from './common/prisma/prisma.module';
import { AiReviewModule } from './modules/ai-review/ai-review.module';
import { CreditsModule } from './modules/credits/credits.module';
import { AnalysisWorker } from './modules/analysis/analysis.worker';
import { ReviewProcessor } from './modules/analysis/review.processor';
import { TokenCleanupJob } from './modules/analysis/token-cleanup.job';
import { PhotosModule } from './modules/photos/photos.module';

/**
 * WorkerModule — process riêng cho BullMQ (`ai-review` + `token-cleanup`),
 * KHÔNG có HTTP layer (spec-sprint-4 FR-S4-2, trả nợ D2).
 *
 * Trước đây `AnalysisWorker` chạy in-process cùng API qua `OnModuleInit`
 * trong AnalysisModule — API scale-to-zero (Cloud Run) sẽ ngừng consume job.
 * Module này tách consumer ra process riêng (`main.worker.ts`), bootstrap
 * qua `NestFactory.createApplicationContext` (không listen port).
 *
 * `AnalysisModule` (API) không còn khai báo AnalysisWorker/TokenCleanupJob —
 * API chỉ enqueue qua `REVIEW_QUEUE`, không consume.
 */
@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true, validate: validateEnv }),
    PrismaModule,
    CreditsModule,
    AiReviewModule,
    PhotosModule,
  ],
  providers: [ReviewProcessor, AnalysisWorker, TokenCleanupJob],
})
export class WorkerModule {}
