import { describe, expect, it, vi } from 'vitest';

import { PrismaService } from '../../common/prisma/prisma.service';
import { CreditsService } from './credits.service';

/**
 * Test CreditsService — path raw SQL rủi ro nhất (EC-S3-1 race, EC-S3-3
 * premium mid-day). Mock $queryRaw/$executeRaw ở tầng đơn vị; hành vi SQL
 * thật (ON CONFLICT guard) cần integration test với Postgres (chưa có DB
 * local run này — ghi nhận trong báo cáo).
 */
function service(opts?: {
  queryRawResult?: Array<{ used: number; quota: number }>;
  findUnique?: { used: number; quota: number } | null;
}) {
  const queryRaw = vi.fn(async () => opts?.queryRawResult ?? []);
  const executeRaw = vi.fn(async () => 1);
  const findUnique = vi.fn(async () => opts?.findUnique ?? null);

  const prisma = {
    $queryRaw: queryRaw,
    $executeRaw: executeRaw,
    credit: { findUnique },
  } as unknown as PrismaService;

  return { svc: new CreditsService(prisma), queryRaw, executeRaw, findUnique };
}

describe('CreditsService (spec FR-S3-4, Rule 2)', () => {
  describe('tryConsume — atomic deduct (EC-S3-1)', () => {
    it('trả remaining khi còn quota (free)', async () => {
      const { svc } = service({ queryRawResult: [{ used: 3, quota: 10 }] });

      const out = await svc.tryConsume('u-1', 'free', 10);

      expect(out).toEqual({ remaining: 7 });
    });

    it('trả null khi hết quota (RETURNING rỗng → 402)', async () => {
      const { svc } = service({ queryRawResult: [] });

      const out = await svc.tryConsume('u-1', 'free', 10);

      expect(out).toBeNull();
    });

    it('premium unlimited: remaining = -1', async () => {
      const { svc } = service({ queryRawResult: [{ used: 42, quota: -1 }] });

      const out = await svc.tryConsume('u-1', 'premium', 10);

      expect(out).toEqual({ remaining: -1 });
    });

    it('premium truyền quota=-1 vào SQL (EC-S3-3: mua premium giữa ngày)', async () => {
      const { svc, queryRaw } = service({ queryRawResult: [{ used: 11, quota: -1 }] });

      await svc.tryConsume('u-1', 'premium', 10);

      // $queryRaw tagged template: [strings, ...values]. quota=-1 phải nằm
      // trong values để EXCLUDED.quota=-1 mở khoá row cũ đã đầy (fix EC-S3-3).
      const values = queryRaw.mock.calls[0]?.slice(1) as unknown[];
      expect(values).toContain(-1);
    });
  });

  describe('refund (Rule 2)', () => {
    it('gọi $executeRaw để giảm used (floor 0 ở SQL)', async () => {
      const { svc, executeRaw } = service();

      await svc.refund('u-1');

      expect(executeRaw).toHaveBeenCalledTimes(1);
    });

    it('dùng executor truyền vào (transaction) thay vì prisma gốc', async () => {
      const { svc } = service();
      const txExecuteRaw = vi.fn(async () => 1);
      const tx = { $executeRaw: txExecuteRaw } as unknown as PrismaService;

      await svc.refund('u-1', undefined, tx);

      expect(txExecuteRaw).toHaveBeenCalledTimes(1);
    });
  });

  describe('status', () => {
    it('free: remaining = quota - used', async () => {
      const { svc } = service({ findUnique: { used: 4, quota: 10 } });

      const out = await svc.status('u-1', 'free', 10);

      expect(out).toEqual({ usedToday: 4, quota: 10, remainingToday: 6 });
    });

    it('premium: remaining = -1 (unlimited)', async () => {
      const { svc } = service({ findUnique: { used: 99, quota: -1 } });

      const out = await svc.status('u-1', 'premium', 10);

      expect(out).toEqual({ usedToday: 99, quota: -1, remainingToday: -1 });
    });

    it('chưa có row hôm nay: used=0, remaining=full quota', async () => {
      const { svc } = service({ findUnique: null });

      const out = await svc.status('u-1', 'free', 10);

      expect(out).toEqual({ usedToday: 0, quota: 10, remainingToday: 10 });
    });
  });
});
