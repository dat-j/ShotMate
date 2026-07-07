import { ExecutionContext } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { describe, expect, it, vi } from 'vitest';

import { AppError } from '../http/http-error.filter';
import { RateLimitRule } from './rate-limit.decorator';
import { RateLimitGuard } from './rate-limit.guard';
import { RateLimitService } from './rate-limit.service';

function context(req: Record<string, unknown>): ExecutionContext {
  return {
    switchToHttp: () => ({ getRequest: () => req }),
    getHandler: () => (): void => undefined,
    getClass: () => class {},
  } as unknown as ExecutionContext;
}

function guard(overrides?: { rules?: RateLimitRule[]; allowed?: boolean; failedOpen?: boolean }) {
  const reflector = {
    getAllAndOverride: vi.fn(() => overrides?.rules),
  } as unknown as Reflector;

  const check = vi.fn(async () => ({
    allowed: overrides?.allowed ?? true,
    failedOpen: overrides?.failedOpen ?? false,
  }));
  const rateLimit = { check } as unknown as RateLimitService;

  return { g: new RateLimitGuard(reflector, rateLimit), check };
}

describe('RateLimitGuard (spec FR-S4-4)', () => {
  it('không có route rule + chưa auth → pass, không gọi Redis', async () => {
    const { g, check } = guard({ rules: undefined });

    const allowed = await g.canActivate(context({}));

    expect(allowed).toBe(true);
    expect(check).not.toHaveBeenCalled();
  });

  it('request đã auth (req.user) → luôn áp default 60/phút/user kể cả không có route rule', async () => {
    const { g, check } = guard({ rules: undefined, allowed: true });

    await g.canActivate(context({ user: { userId: 'u-1' } }));

    expect(check).toHaveBeenCalledWith(
      expect.objectContaining({ key: 'ratelimit:authenticated-default:u-1', limit: 60, windowSeconds: 60 }),
    );
  });

  it('vượt default authenticated limit → 429 RATE_LIMITED', async () => {
    const { g } = guard({ rules: undefined, allowed: false });

    await expect(g.canActivate(context({ user: { userId: 'u-1' } }))).rejects.toMatchObject({
      code: 'RATE_LIMITED',
    });
    await expect(g.canActivate(context({ user: { userId: 'u-1' } }))).rejects.toBeInstanceOf(
      AppError,
    );
  });

  it('route rule keyBy=email đọc email lowercase từ body', async () => {
    const rules: RateLimitRule[] = [
      { name: 'magic-link-email', limit: 3, windowSeconds: 900, keyBy: 'email' },
    ];
    const { g, check } = guard({ rules, allowed: true });

    await g.canActivate(context({ body: { email: 'User@Example.com' } }));

    expect(check).toHaveBeenCalledWith(
      expect.objectContaining({ key: 'ratelimit:magic-link-email:user@example.com' }),
    );
  });

  it('route rule keyBy=ip đọc req.ip', async () => {
    const rules: RateLimitRule[] = [
      { name: 'magic-link-ip', limit: 10, windowSeconds: 3600, keyBy: 'ip' },
    ];
    const { g, check } = guard({ rules, allowed: true });

    await g.canActivate(context({ ip: '203.0.113.5' }));

    expect(check).toHaveBeenCalledWith(
      expect.objectContaining({ key: 'ratelimit:magic-link-ip:203.0.113.5' }),
    );
  });

  it('magic-link: CẢ 2 rule (email + ip) đều được kiểm tra', async () => {
    const rules: RateLimitRule[] = [
      { name: 'magic-link-email', limit: 3, windowSeconds: 900, keyBy: 'email' },
      { name: 'magic-link-ip', limit: 10, windowSeconds: 3600, keyBy: 'ip' },
    ];
    const { g, check } = guard({ rules, allowed: true });

    await g.canActivate(context({ ip: '203.0.113.5', body: { email: 'a@b.com' } }));

    expect(check).toHaveBeenCalledTimes(2);
  });

  it('vượt 1 trong 2 rule (email) → 429 dù ip còn hạn mức', async () => {
    const rules: RateLimitRule[] = [
      { name: 'magic-link-email', limit: 3, windowSeconds: 900, keyBy: 'email' },
      { name: 'magic-link-ip', limit: 10, windowSeconds: 3600, keyBy: 'ip' },
    ];
    const reflector = { getAllAndOverride: vi.fn(() => rules) } as unknown as Reflector;
    const check = vi
      .fn()
      .mockResolvedValueOnce({ allowed: false, failedOpen: false }) // email vượt
      .mockResolvedValueOnce({ allowed: true, failedOpen: false }); // ip còn hạn mức
    const rateLimit = { check } as unknown as RateLimitService;
    const g = new RateLimitGuard(reflector, rateLimit);

    await expect(
      g.canActivate(context({ ip: '203.0.113.5', body: { email: 'a@b.com' } })),
    ).rejects.toMatchObject({ code: 'RATE_LIMITED' });
  });

  it('review-user rule keyBy=user đọc req.user.userId', async () => {
    const rules: RateLimitRule[] = [
      { name: 'review-user', limit: 10, windowSeconds: 60, keyBy: 'user' },
    ];
    const { g, check } = guard({ rules, allowed: true });

    await g.canActivate(context({ user: { userId: 'u-42' } }));

    // default authenticated rule + review-user rule = 2 lệnh check.
    expect(check).toHaveBeenCalledWith(
      expect.objectContaining({ key: 'ratelimit:review-user:u-42', limit: 10, windowSeconds: 60 }),
    );
  });

  it('EC-S4-1: RateLimitService fail-open (Redis chết) → guard vẫn pass', async () => {
    const { g } = guard({ rules: undefined, allowed: true, failedOpen: true });

    const allowed = await g.canActivate(context({ user: { userId: 'u-1' } }));

    expect(allowed).toBe(true);
  });

  it('keyBy=email không resolve được (thiếu body.email) → bỏ qua rule đó, không chặn nhầm', async () => {
    const rules: RateLimitRule[] = [
      { name: 'magic-link-email', limit: 3, windowSeconds: 900, keyBy: 'email' },
    ];
    const { g, check } = guard({ rules, allowed: true });

    const allowed = await g.canActivate(context({}));

    expect(allowed).toBe(true);
    expect(check).not.toHaveBeenCalled();
  });
});
