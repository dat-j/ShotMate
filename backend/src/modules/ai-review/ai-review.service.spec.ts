import { ConfigService } from '@nestjs/config';
import { describe, expect, it, vi } from 'vitest';

import { AiReviewProvider, ReviewResult } from './ai-review.provider';
import { AiReviewService } from './ai-review.service';
import { extractJson } from './claude.provider';

const result: ReviewResult = {
  scores: { composition: 90, lighting: 85, focus: 100, background: 70 },
  explanation: 'Bố cục tốt.',
  suggestions: ['Lùi lại 30cm'],
};

function fakeProvider(
  name: 'claude' | 'gemini',
  impl: () => Promise<ReviewResult>,
): AiReviewProvider {
  return { name, review: vi.fn(impl) };
}

function service(providers: AiReviewProvider[], primary: string) {
  const config = { get: () => primary } as unknown as ConfigService;
  return new AiReviewService(providers, config);
}

describe('AiReviewService (ADR-0004)', () => {
  it('dùng provider primary theo config', async () => {
    const claude = fakeProvider('claude', async () => result);
    const gemini = fakeProvider('gemini', async () => result);

    const out = await service([claude, gemini], 'gemini').review('img', {});

    expect(out.provider).toBe('gemini');
    expect(claude.review).not.toHaveBeenCalled();
  });

  it('failover sang provider còn lại khi primary lỗi', async () => {
    const claude = fakeProvider('claude', async () => {
      throw new Error('rate limited');
    });
    const gemini = fakeProvider('gemini', async () => result);

    const out = await service([claude, gemini], 'claude').review('img', {});

    expect(out.provider).toBe('gemini');
    expect(out.scores.composition).toBe(90);
  });

  it('ném lỗi cuối khi tất cả provider lỗi (worker retry)', async () => {
    const claude = fakeProvider('claude', async () => {
      throw new Error('down-1');
    });
    const gemini = fakeProvider('gemini', async () => {
      throw new Error('down-2');
    });

    await expect(
      service([claude, gemini], 'claude').review('img', {}),
    ).rejects.toThrow('down-2');
  });
});

describe('extractJson', () => {
  it('bóc JSON khỏi markdown fence', () => {
    expect(extractJson('```json\n{"a":1}\n```')).toBe('{"a":1}');
  });

  it('giữ nguyên plain JSON', () => {
    expect(extractJson('{"a":1}')).toBe('{"a":1}');
  });
});
