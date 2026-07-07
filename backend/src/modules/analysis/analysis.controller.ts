import { Controller, Get, HttpCode, Param, Post } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

import { AuthUser, CurrentUser } from '../../common/auth/current-user.decorator';
import { RateLimit } from '../../common/rate-limit/rate-limit.decorator';
import { SubscriptionsService } from '../subscriptions/subscriptions.service';
import { AnalysisService, RequestReviewResult, ReviewResultView } from './analysis.service';

/**
 * AnalysisController — POST/GET /photos/:id/review (spec FR-S3-3).
 * Plan cho quota luôn đọc từ SubscriptionsService.currentPlan (DB), KHÔNG
 * dùng JWT plan claim — JWT plan chỉ để hint UI (spec Rule 3, FR-S3-1).
 */
@Controller('photos/:id/review')
export class AnalysisController {
  constructor(
    private readonly analysis: AnalysisService,
    private readonly subscriptions: SubscriptionsService,
    private readonly config: ConfigService,
  ) {}

  // FR-S4-4: 10/user/phút, cộng dồn với default authenticated 60/phút/user.
  @RateLimit({ name: 'review-user', limit: 10, windowSeconds: 60, keyBy: 'user' })
  @Post()
  @HttpCode(202)
  async requestReview(
    @CurrentUser() user: AuthUser,
    @Param('id') photoId: string,
  ): Promise<RequestReviewResult> {
    const { plan } = await this.subscriptions.currentPlan(user.userId);
    const freeQuota = this.config.get<number>('FREE_DAILY_QUOTA') ?? 10;
    return this.analysis.requestReview(user.userId, plan, freeQuota, photoId);
  }

  @Get()
  getReview(
    @CurrentUser() user: AuthUser,
    @Param('id') photoId: string,
  ): Promise<ReviewResultView> {
    return this.analysis.getReview(user.userId, photoId);
  }
}
