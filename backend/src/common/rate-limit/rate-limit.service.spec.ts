import { describe, expect, it, vi } from 'vitest';

import { RateLimitService } from './rate-limit.service';

function service(overrides?: {
  incr?: (key: string) => Promise<number>;
  expire?: () => Promise<number>;
}) {
  const incr = vi.fn(overrides?.incr ?? (async () => 1));
  const expire = vi.fn(overrides?.expire ?? (async () => 1));
  const redis = { incr, expire } as unknown as import('ioredis').default;
  return { svc: new RateLimitService(redis), incr, expire };
}

describe('RateLimitService.check (spec FR-S4-4, EC-S4-1)', () => {
  it('dưới giới hạn → allowed=true, không fail-open', async () => {
    const { svc } = service({ incr: async () => 1 });

    const result = await svc.check({ key: 'k1', limit: 3, windowSeconds: 60 });

    expect(result).toEqual({ allowed: true, failedOpen: false });
  });

  it('đặt TTL chỉ ở lần đầu tiên (count === 1)', async () => {
    const { svc, expire } = service({ incr: async () => 1 });

    await svc.check({ key: 'k1', limit: 3, windowSeconds: 900 });

    expect(expire).toHaveBeenCalledWith('k1', 900);
  });

  it('không đặt lại TTL cho các lần incr tiếp theo trong cùng window', async () => {
    const { svc, expire } = service({ incr: async () => 2 });

    await svc.check({ key: 'k1', limit: 3, windowSeconds: 900 });

    expect(expire).not.toHaveBeenCalled();
  });

  it('vượt giới hạn (count > limit) → allowed=false', async () => {
    const { svc } = service({ incr: async () => 4 });

    const result = await svc.check({ key: 'k1', limit: 3, windowSeconds: 60 });

    expect(result).toEqual({ allowed: false, failedOpen: false });
  });

  it('đúng bằng limit → vẫn allowed (limit là số request tối đa)', async () => {
    const { svc } = service({ incr: async () => 3 });

    const result = await svc.check({ key: 'k1', limit: 3, windowSeconds: 60 });

    expect(result.allowed).toBe(true);
  });

  it('EC-S4-1: Redis lỗi (incr throw) → fail-open, allowed=true', async () => {
    const { svc } = service({
      incr: async () => {
        throw new Error('ECONNREFUSED');
      },
    });

    const result = await svc.check({ key: 'k1', limit: 3, windowSeconds: 60 });

    expect(result).toEqual({ allowed: true, failedOpen: true });
  });

  it('EC-S4-1: Redis lỗi ở bước expire cũng fail-open', async () => {
    const { svc } = service({
      incr: async () => 1,
      expire: async () => {
        throw new Error('ECONNREFUSED');
      },
    });

    const result = await svc.check({ key: 'k1', limit: 3, windowSeconds: 60 });

    expect(result).toEqual({ allowed: true, failedOpen: true });
  });
});
