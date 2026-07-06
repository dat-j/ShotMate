import { Module } from '@nestjs/common';

import { AiReviewModule } from '../ai-review/ai-review.module';
import { CreditsModule } from '../credits/credits.module';
import { PhotosModule } from '../photos/photos.module';
import { SubscriptionsService } from '../subscriptions/subscriptions.service';
import { AnalysisController } from './analysis.controller';
import { AnalysisService } from './analysis.service';
import { AnalysisWorker } from './analysis.worker';
import { reviewQueueProvider } from './review.queue';
import { ReviewProcessor } from './review.processor';

/**
 * AnalysisModule — enqueue BullMQ review job, poll kết quả (spec FR-S3-3,
 * ADR-0002).
 *
 * SubscriptionsService được khai báo local (thay vì import
 * SubscriptionsModule) để tránh đụng độ với worker khác đang implement
 * subscriptions.module.ts — service này chỉ phụ thuộc PrismaService
 * (global) nên an toàn khi tái tạo provider ở đây (giống UsersModule).
 */
@Module({
  imports: [CreditsModule, AiReviewModule, PhotosModule],
  controllers: [AnalysisController],
  providers: [
    AnalysisService,
    ReviewProcessor,
    AnalysisWorker,
    SubscriptionsService,
    reviewQueueProvider,
  ],
})
export class AnalysisModule {}
