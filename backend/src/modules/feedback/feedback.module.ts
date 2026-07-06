import { Module } from '@nestjs/common';

import { FeedbackController } from './feedback.controller';
import { FeedbackService } from './feedback.service';

/**
 * FeedbackModule — implement Sprint 3 (spec FR-S3-10). POST /feedback
 * (hint|score|review, rating ±1). Cắt thứ ba nếu trễ (spec Rule 10).
 */
@Module({
  controllers: [FeedbackController],
  providers: [FeedbackService],
})
export class FeedbackModule {}
