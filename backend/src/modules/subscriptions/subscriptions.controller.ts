import { Body, Controller, Headers, HttpCode, Logger, Post } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

import { Public } from '../../common/auth/public.decorator';
import { AuthUser, CurrentUser } from '../../common/auth/current-user.decorator';
import { safeEqual } from '../../common/crypto/token.util';
import { AppError } from '../../common/http/http-error.filter';
import {
  REVENUECAT_ACTIVE_EVENT_TYPES,
  REVENUECAT_INACTIVE_EVENT_TYPES,
  RawRevenueCatWebhookBody,
  revenueCatWebhookBodySchema,
} from './dto/revenuecat-webhook.dto';
import { VerifySubscriptionDto } from './dto/verify-subscription.dto';
import { PlanStatus, SubscriptionsService } from './subscriptions.service';

/**
 * SubscriptionsController — webhook RevenueCat (public, secret header) +
 * verify fallback (authenticated). Spec FR-S3-5, Rule 3.
 */
@Controller()
export class SubscriptionsController {
  private readonly logger = new Logger(SubscriptionsController.name);

  constructor(
    private readonly subscriptions: SubscriptionsService,
    private readonly config: ConfigService,
  ) {}

  /**
   * POST /webhooks/revenuecat — Authorization header so sánh constant-time
   * với REVENUECAT_WEBHOOK_SECRET (spec Rule 3, security.md). app_user_id
   * RevenueCat == User.id ShotMate (client gửi uuid của chính nó).
   */
  @Public()
  @Post('webhooks/revenuecat')
  @HttpCode(200)
  async handleWebhook(
    @Headers('authorization') authorization: string | undefined,
    @Body() body: RawRevenueCatWebhookBody,
  ): Promise<Record<string, never>> {
    // Secret check chạy trước và độc lập với validation payload — 401 ưu
    // tiên hơn 422 nếu secret sai, tránh lộ thông tin qua timing/response
    // khác nhau (security.md, spec FR-S4-5/D4).
    const secret = this.config.get<string>('REVENUECAT_WEBHOOK_SECRET');
    if (!secret || !authorization || !safeEqual(authorization, secret)) {
      throw new AppError(401, 'WEBHOOK_UNAUTHORIZED', 'Invalid webhook secret');
    }

    const parsed = revenueCatWebhookBodySchema.safeParse(body);
    if (!parsed.success) {
      // Không log toàn bộ payload (có thể chứa PII) — chỉ type (nếu có) +
      // lý do lỗi zod.
      this.logger.warn(
        `RevenueCat webhook payload invalid type=${body?.event?.type ?? 'n/a'} reason=${parsed.error.issues.map((i) => `${i.path.join('.')}:${i.message}`).join('; ')}`,
      );
      throw new AppError(422, 'VALIDATION_FAILED', 'Invalid RevenueCat webhook payload');
    }

    const { event } = parsed.data;
    const appUserId = event.app_user_id;

    const isActive = REVENUECAT_ACTIVE_EVENT_TYPES.has(event.type);
    const isInactive = REVENUECAT_INACTIVE_EVENT_TYPES.has(event.type);
    if (!isActive && !isInactive) {
      return {};
    }

    await this.subscriptions.upsertFromEntitlement({
      userId: appUserId,
      plan: isActive ? 'premium' : 'free',
      store: event.store ?? null,
      expiresAt: event.expiration_at_ms ? new Date(event.expiration_at_ms) : null,
      receiptRef: appUserId,
    });

    return {};
  }

  /**
   * POST /subscriptions/verify — fallback khi webhook trễ (spec Rule 3,
   * FR-S3-5). Không có network call thật tới RevenueCat REST API trong
   * bản này — đọc thẳng subscription hiện hành từ DB.
   *
   * TODO: fetch entitlement from RevenueCat REST API bằng REVENUECAT_API_KEY
   * khi có network call thật (hiện tại chỉ trả lại currentPlan đã lưu).
   */
  @Post('subscriptions/verify')
  @HttpCode(200)
  async verify(
    @CurrentUser() user: AuthUser,
    @Body() dto: VerifySubscriptionDto,
  ): Promise<PlanStatus> {
    if (dto.appUserId !== undefined && dto.appUserId.trim().length === 0) {
      throw new AppError(
        400,
        'SUBSCRIPTION_INVALID_RECEIPT',
        'appUserId must not be blank',
      );
    }

    return this.subscriptions.currentPlan(user.userId);
  }
}
