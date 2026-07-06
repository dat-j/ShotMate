import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

import { AppError } from '../../common/http/http-error.filter';
import { PrismaService } from '../../common/prisma/prisma.service';
import { StorageService } from '../photos/storage.service';
import { CreditsService } from '../credits/credits.service';
import { SubscriptionsService } from '../subscriptions/subscriptions.service';

export interface MeResult {
  user: {
    id: string;
    email: string;
    displayName: string | null;
  };
  subscription: {
    plan: 'free' | 'premium';
    expiresAt: Date | null;
  };
  credits: {
    usedToday: number;
    quota: number; // -1 = unlimited (premium)
    remainingToday: number; // -1 = unlimited
  };
}

/**
 * UsersService — account management (spec FR-S3-7): GET/DELETE /me.
 * userId LUÔN đến từ @CurrentUser() (JWT), không bao giờ từ body/params.
 */
@Injectable()
export class UsersService {
  private readonly logger = new Logger(UsersService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly subscriptions: SubscriptionsService,
    private readonly credits: CreditsService,
    private readonly config: ConfigService,
    private readonly storage: StorageService,
  ) {}

  async getMe(userId: string): Promise<MeResult> {
    const user = await this.prisma.user.findUnique({ where: { id: userId } });
    if (!user) {
      throw new AppError(401, 'AUTH_TOKEN_INVALID', 'User not found');
    }

    const subscription = await this.subscriptions.currentPlan(userId);
    const freeQuota = this.config.get<number>('FREE_DAILY_QUOTA') ?? 10;
    const credits = await this.credits.status(userId, subscription.plan, freeQuota);

    return {
      user: {
        id: user.id,
        email: user.email,
        displayName: user.displayName,
      },
      subscription,
      credits,
    };
  }

  /**
   * Xoá account (spec FR-S3-7, EC-S3-11, App Store 5.1.1(v)). Prisma cascade
   * xoá subscription/photos/analyses/scores/credits/refreshTokens qua
   * onDelete: Cascade đã khai trong schema. Local data trên máy user giữ
   * nguyên (không thuộc phạm vi backend).
   *
   * GCS purge là best-effort: xoá account PHẢI thành công (nghĩa vụ store),
   * nên storage chưa cấu hình / lỗi mạng KHÔNG được chặn — chỉ log để dọn sau.
   */
  async deleteMe(userId: string): Promise<void> {
    await this.prisma.user.delete({ where: { id: userId } });
    try {
      await this.storage.deletePrefix(`photos/${userId}/`);
    } catch (error) {
      // Storage chưa wire (503 STORAGE_UNAVAILABLE) hoặc lỗi mạng — không
      // chặn việc xoá account. Dọn ảnh orphan qua lifecycle rule/job sau.
      this.logger.warn(
        `Account ${userId} deleted; GCS prefix purge deferred: ${String(error)}`,
      );
    }
  }
}
