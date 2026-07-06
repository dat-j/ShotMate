import { ConfigService } from '@nestjs/config';
import { describe, expect, it, vi } from 'vitest';

import { AppError } from '../../common/http/http-error.filter';
import { PrismaService } from '../../common/prisma/prisma.service';
import { StorageService } from '../photos/storage.service';
import { CreditsService } from '../credits/credits.service';
import { SubscriptionsService } from '../subscriptions/subscriptions.service';
import { UsersService } from './users.service';

function service(overrides?: {
  user?: { id: string; email: string; displayName: string | null } | null;
  plan?: { plan: 'free' | 'premium'; expiresAt: Date | null };
  credits?: { usedToday: number; quota: number; remainingToday: number };
  freeQuota?: number;
  deletePrefix?: () => Promise<void>;
}) {
  const prisma = {
    user: {
      findUnique: vi.fn(async () => overrides?.user ?? null),
      delete: vi.fn(async () => undefined),
    },
  } as unknown as PrismaService;

  const subscriptions = {
    currentPlan: vi.fn(
      async () => overrides?.plan ?? { plan: 'free' as const, expiresAt: null },
    ),
  } as unknown as SubscriptionsService;

  const credits = {
    status: vi.fn(
      async () =>
        overrides?.credits ?? { usedToday: 0, quota: 10, remainingToday: 10 },
    ),
  } as unknown as CreditsService;

  const config = {
    get: () => overrides?.freeQuota ?? 10,
  } as unknown as ConfigService;

  const storage = {
    deletePrefix: vi.fn(overrides?.deletePrefix ?? (async () => undefined)),
  } as unknown as StorageService;

  return {
    svc: new UsersService(prisma, subscriptions, credits, config, storage),
    prisma,
    subscriptions,
    credits,
    storage,
  };
}

describe('UsersService (spec FR-S3-4 /me, FR-S3-7 account, EC-S3-11)', () => {
  describe('getMe', () => {
    it('trả shape gộp user + subscription + credits', async () => {
      const user = { id: 'u-1', email: 'a@b.com', displayName: 'Dat' };
      const plan = { plan: 'premium' as const, expiresAt: new Date('2027-01-01') };
      const creditsStatus = { usedToday: 3, quota: -1, remainingToday: -1 };
      const { svc, subscriptions, credits } = service({ user, plan, credits: creditsStatus });

      const result = await svc.getMe('u-1');

      expect(result).toEqual({
        user: { id: 'u-1', email: 'a@b.com', displayName: 'Dat' },
        subscription: plan,
        credits: creditsStatus,
      });
      expect(subscriptions.currentPlan).toHaveBeenCalledWith('u-1');
      expect(credits.status).toHaveBeenCalledWith('u-1', 'premium', 10);
    });

    it('ném AUTH_TOKEN_INVALID 401 khi user không tồn tại', async () => {
      const { svc } = service({ user: null });

      await expect(svc.getMe('missing-user')).rejects.toMatchObject({
        code: 'AUTH_TOKEN_INVALID',
      });
      await svc.getMe('missing-user').catch((err: AppError) => {
        expect(err.getStatus()).toBe(401);
      });
    });

    it('dùng FREE_DAILY_QUOTA từ ConfigService cho plan free', async () => {
      const user = { id: 'u-2', email: 'x@y.com', displayName: null };
      const { svc, credits } = service({
        user,
        plan: { plan: 'free', expiresAt: null },
        freeQuota: 25,
      });

      await svc.getMe('u-2');

      expect(credits.status).toHaveBeenCalledWith('u-2', 'free', 25);
    });
  });

  describe('deleteMe', () => {
    it('gọi prisma.user.delete với đúng id + xoá GCS prefix của user', async () => {
      const { svc, prisma, storage } = service();

      await svc.deleteMe('u-3');

      expect(prisma.user.delete).toHaveBeenCalledWith({ where: { id: 'u-3' } });
      expect(storage.deletePrefix).toHaveBeenCalledWith('photos/u-3/');
    });

    it('GCS purge best-effort: storage lỗi KHÔNG chặn xoá account (EC-S3-11)', async () => {
      const { svc, prisma } = service({
        deletePrefix: async () => {
          throw new AppError(503, 'STORAGE_UNAVAILABLE', 'chưa cấu hình');
        },
      });

      // Account vẫn xoá thành công dù storage ném lỗi.
      await expect(svc.deleteMe('u-4')).resolves.toBeUndefined();
      expect(prisma.user.delete).toHaveBeenCalledWith({ where: { id: 'u-4' } });
    });
  });
});
