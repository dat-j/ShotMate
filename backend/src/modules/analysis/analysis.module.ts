import { Module } from '@nestjs/common';

import { AiReviewModule } from '../ai-review/ai-review.module';
import { CreditsModule } from '../credits/credits.module';
import { PhotosModule } from '../photos/photos.module';
import { SubscriptionsService } from '../subscriptions/subscriptions.service';
import { AnalysisController } from './analysis.controller';
import { AnalysisService } from './analysis.service';
import { reviewQueueProvider } from './review.queue';

/**
 * AnalysisModule (API process) — enqueue BullMQ review job + poll kết quả
 * (spec FR-S3-3, ADR-0002). KHÔNG consume job — `AnalysisWorker` chạy trong
 * process riêng (`main.worker.ts`/`WorkerModule`, spec-sprint-4 FR-S4-2, trả
 * nợ D2) để API scale-to-zero không làm chết consumer.
 *
 * SubscriptionsService được khai báo local (thay vì import
 * SubscriptionsModule) để tránh đụng độ với worker khác đang implement
 * subscriptions.module.ts — service này chỉ phụ thuộc PrismaService
 * (global) nên an toàn khi tái tạo provider ở đây (giống UsersModule).
 */
@Module({
  imports: [CreditsModule, AiReviewModule, PhotosModule],
  controllers: [AnalysisController],
  providers: [AnalysisService, SubscriptionsService, reviewQueueProvider],
})
export class AnalysisModule {}
