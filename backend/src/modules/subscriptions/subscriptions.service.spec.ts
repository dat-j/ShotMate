import { describe, expect, it, vi } from 'vitest';

import { PrismaService } from '../../common/prisma/prisma.service';
import { SubscriptionsService } from './subscriptions.service';

function service(overrides?: {
  findUnique?: unknown;
  upsert?: unknown;
}) {
  const prisma = {
    subscription: {
      findUnique: vi.fn(async () => overrides?.findUnique ?? null),
      upsert: vi.fn(async () => overrides?.upsert ?? undefined),
    },
  } as unknown as PrismaService;

  return { svc: new SubscriptionsService(prisma), prisma };
}

describe('SubscriptionsService (spec FR-S3-5, Rule 3, EC-S3-9)', () => {
  describe('currentPlan', () => {
    it('trả free khi không có subscription', async () => {
      const { svc } = service({ findUnique: null });

      const result = await svc.currentPlan('u-1');

      expect(result).toEqual({ plan: 'free', expiresAt: null });
    });

    it('trả free khi premium đã hết hạn (EC-S3-9, không cần cron)', async () => {
      const expired = new Date(Date.now() - 60_000);
      const { svc } = service({
        findUnique: { userId: 'u-2', plan: 'premium', expiresAt: expired },
      });

      const result = await svc.currentPlan('u-2');

      expect(result).toEqual({ plan: 'free', expiresAt: expired });
    });

    it('trả premium khi còn hạn', async () => {
      const future = new Date(Date.now() + 60_000);
      const { svc } = service({
        findUnique: { userId: 'u-3', plan: 'premium', expiresAt: future },
      });

      const result = await svc.currentPlan('u-3');

      expect(result).toEqual({ plan: 'premium', expiresAt: future });
    });

    it('trả premium khi expiresAt null (không giới hạn)', async () => {
      const { svc } = service({
        findUnique: { userId: 'u-4', plan: 'premium', expiresAt: null },
      });

      const result = await svc.currentPlan('u-4');

      expect(result).toEqual({ plan: 'premium', expiresAt: null });
    });
  });

  describe('upsertFromEntitlement', () => {
    it('gọi prisma.subscription.upsert với đúng userId + shape', async () => {
      const future = new Date(Date.now() + 100_000);
      const { svc, prisma } = service({
        upsert: { userId: 'u-5', plan: 'premium', store: 'google', expiresAt: future, receiptRef: 'u-5' },
      });

      const result = await svc.upsertFromEntitlement({
        userId: 'u-5',
        plan: 'premium',
        store: 'google',
        expiresAt: future,
        receiptRef: 'u-5',
      });

      expect(prisma.subscription.upsert).toHaveBeenCalledWith({
        where: { userId: 'u-5' },
        create: {
          userId: 'u-5',
          plan: 'premium',
          store: 'google',
          expiresAt: future,
          receiptRef: 'u-5',
        },
        update: {
          plan: 'premium',
          store: 'google',
          expiresAt: future,
          receiptRef: 'u-5',
        },
      });
      expect(result).toEqual({ plan: 'premium', expiresAt: future });
    });

    it('map plan=free (EXPIRATION/CANCELLATION) đúng shape trả về', async () => {
      const { svc, prisma } = service({
        upsert: { userId: 'u-6', plan: 'free', store: null, expiresAt: null, receiptRef: null },
      });

      const result = await svc.upsertFromEntitlement({
        userId: 'u-6',
        plan: 'free',
      });

      expect(prisma.subscription.upsert).toHaveBeenCalledWith({
        where: { userId: 'u-6' },
        create: { userId: 'u-6', plan: 'free', store: null, expiresAt: null, receiptRef: null },
        update: { plan: 'free', store: null, expiresAt: null, receiptRef: null },
      });
      expect(result).toEqual({ plan: 'free', expiresAt: null });
    });
  });
});
