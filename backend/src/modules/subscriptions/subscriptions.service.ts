import { Injectable, Logger } from '@nestjs/common';

import { PrismaService } from '../../common/prisma/prisma.service';

export interface PlanStatus {
  plan: 'free' | 'premium';
  expiresAt: Date | null;
}

export interface EntitlementUpdate {
  userId: string;
  plan: 'free' | 'premium';
  store?: string | null;
  expiresAt?: Date | null;
  receiptRef?: string | null;
}

/**
 * Nguồn sự thật về plan (spec Rule 3: không tin client). Premium chỉ khi có
 * Subscription plan=premium VÀ chưa hết hạn — hết hạn đọc ra free ngay,
 * không cần cron (EC-S3-9).
 */
@Injectable()
export class SubscriptionsService {
  private readonly logger = new Logger(SubscriptionsService.name);

  constructor(private readonly prisma: PrismaService) {}

  async currentPlan(userId: string): Promise<PlanStatus> {
    const sub = await this.prisma.subscription.findUnique({ where: { userId } });
    if (!sub || sub.plan !== 'premium') {
      return { plan: 'free', expiresAt: sub?.expiresAt ?? null };
    }
    const active = !sub.expiresAt || sub.expiresAt.getTime() > Date.now();
    return {
      plan: active ? 'premium' : 'free',
      expiresAt: sub.expiresAt,
    };
  }

  /**
   * Upsert Subscription từ entitlement RevenueCat (webhook FR-S3-5) hoặc
   * fallback verify. Audit log thay đổi subscription (security.md — Repudiation).
   */
  async upsertFromEntitlement(entitlement: EntitlementUpdate): Promise<PlanStatus> {
    const { userId, plan, store, expiresAt, receiptRef } = entitlement;

    const sub = await this.prisma.subscription.upsert({
      where: { userId },
      create: {
        userId,
        plan,
        store: store ?? null,
        expiresAt: expiresAt ?? null,
        receiptRef: receiptRef ?? null,
      },
      update: {
        plan,
        store: store ?? null,
        expiresAt: expiresAt ?? null,
        receiptRef: receiptRef ?? null,
      },
    });

    this.logger.log(
      `Subscription updated userId=${userId} plan=${sub.plan} store=${sub.store ?? 'n/a'}`,
    );

    return { plan: sub.plan === 'premium' ? 'premium' : 'free', expiresAt: sub.expiresAt };
  }
}
