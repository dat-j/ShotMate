import { describe, expect, it, vi } from 'vitest';

import { PrismaService } from '../../common/prisma/prisma.service';
import { AiReviewService } from '../ai-review/ai-review.service';
import { CreditsService } from '../credits/credits.service';
import { StorageService } from '../photos/storage.service';
import { ReviewProcessor } from './review.processor';

const ANALYSIS_ID = 'analysis-1';
const PHOTO_ID = 'photo-1';
const USER_ID = 'u-1';

function processor(overrides?: {
  reviewResult?: {
    scores: { composition: number; lighting: number; focus: number; background: number };
    explanation: string;
    suggestions: string[];
    provider: 'claude' | 'gemini';
  };
  reviewError?: Error;
}) {
  const analysis = {
    id: ANALYSIS_ID,
    photoId: PHOTO_ID,
    status: 'queued',
    provider: 'pending',
    photo: {
      id: PHOTO_ID,
      userId: USER_ID,
      storagePath: `photos/${USER_ID}/${PHOTO_ID}.jpg`,
      sceneType: 'portrait',
    },
  };

  const findUniqueOrThrow = vi.fn(async () => analysis);
  const findUnique = vi.fn(async () => analysis);
  const update = vi.fn(async () => undefined);
  const upsert = vi.fn(async () => undefined);

  // $transaction dùng ở 2 dạng: array (process) và callback (handleFinalFailure).
  // Callback nhận tx = chính prisma mock (update chạy trong đó).
  const prismaRef: { current?: PrismaService } = {};
  const $transaction = vi.fn(async (arg: unknown) => {
    if (typeof arg === 'function') {
      return (arg as (tx: PrismaService) => Promise<unknown>)(prismaRef.current!);
    }
    return Promise.all(arg as Promise<unknown>[]);
  });

  const prisma = {
    analysis: { findUniqueOrThrow, findUnique, update },
    score: { upsert },
    $transaction,
  } as unknown as PrismaService;
  prismaRef.current = prisma;

  const getObjectBase64 = vi.fn(async () => 'base64-image-data');
  const storage = { getObjectBase64 } as unknown as StorageService;

  const review = overrides?.reviewError
    ? vi.fn(async () => {
        throw overrides.reviewError;
      })
    : vi.fn(
        async () =>
          overrides?.reviewResult ?? {
            scores: { composition: 90, lighting: 80, focus: 95, background: 70 },
            explanation: 'Tốt lắm',
            suggestions: ['Lùi lại 30cm'],
            provider: 'claude' as const,
          },
      );
  const aiReview = { review } as unknown as AiReviewService;

  const refund = vi.fn(async () => undefined);
  const credits = { refund } as unknown as CreditsService;

  return {
    proc: new ReviewProcessor(prisma, storage, aiReview, credits),
    prisma,
    storage,
    aiReview,
    credits,
    findUniqueOrThrow,
    update,
    upsert,
    $transaction,
    refund,
  };
}

describe('ReviewProcessor (spec FR-S3-3, Rule 7, EC-S3-2)', () => {
  describe('process', () => {
    it('thành công: tải ảnh, gọi AiReviewService, ghi done + Score', async () => {
      const { proc, storage, aiReview, prisma, upsert } = processor();

      await proc.process(ANALYSIS_ID);

      expect(storage.getObjectBase64).toHaveBeenCalledWith(`photos/${USER_ID}/${PHOTO_ID}.jpg`);
      expect(aiReview.review).toHaveBeenCalledWith('base64-image-data', {
        sceneType: 'portrait',
      });
      expect(prisma.$transaction).toHaveBeenCalled();
      expect(upsert).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { analysisId: ANALYSIS_ID },
          create: expect.objectContaining({
            analysisId: ANALYSIS_ID,
            composition: 90,
            lighting: 80,
            focus: 95,
            background: 70,
          }),
        }),
      );
    });

    it('lan truyền lỗi khi AI review fail (worker retry theo backoff)', async () => {
      const { proc } = processor({ reviewError: new Error('all providers down') });

      await expect(proc.process(ANALYSIS_ID)).rejects.toThrow('all providers down');
    });
  });

  describe('handleFinalFailure', () => {
    it('set status=failed + hoàn 1 credit TRONG cùng transaction (EC-S3-2)', async () => {
      const { proc, prisma, refund, $transaction } = processor();

      await proc.handleFinalFailure(ANALYSIS_ID, USER_ID);

      // Cả update lẫn refund chạy trong $transaction (Rule 2: cùng transaction).
      expect($transaction).toHaveBeenCalledTimes(1);
      expect(prisma.analysis.update).toHaveBeenCalledWith({
        where: { id: ANALYSIS_ID },
        data: { status: 'failed' },
      });
      // refund nhận executor (tx) làm tham số thứ 3 để chạy trong transaction.
      expect(refund).toHaveBeenCalledWith(USER_ID, undefined, expect.anything());
    });
  });
});
