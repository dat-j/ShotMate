import { describe, expect, it, vi } from 'vitest';

import { AppError } from '../../common/http/http-error.filter';
import { PrismaService } from '../../common/prisma/prisma.service';
import { CreditsService } from '../credits/credits.service';
import { PhotosService } from '../photos/photos.service';
import { AnalysisService } from './analysis.service';

const PHOTO_ID = '11111111-1111-1111-1111-111111111111';

type PhotoRow = {
  id: string;
  userId: string;
  storagePath: string | null;
};

function service(overrides?: {
  photo?: PhotoRow;
  photoError?: AppError;
  existingInProgress?: unknown;
  consumeResult?: { remaining: number } | null;
  createdAnalysisId?: string;
}) {
  const findOwned = overrides?.photoError
    ? vi.fn(async () => {
        throw overrides.photoError;
      })
    : vi.fn(
        async () =>
          overrides?.photo ?? {
            id: PHOTO_ID,
            userId: 'u-1',
            storagePath: `photos/u-1/${PHOTO_ID}.jpg`,
          },
      );

  const photos = { findOwned } as unknown as PhotosService;

  const findFirst = vi.fn(async () => overrides?.existingInProgress ?? null);
  const created = { id: overrides?.createdAnalysisId ?? 'analysis-1' };
  const create = vi.fn(async () => created);

  const prisma = {
    analysis: { findFirst, create },
  } as unknown as PrismaService;

  const tryConsume = vi.fn(async () =>
    'consumeResult' in (overrides ?? {}) ? overrides!.consumeResult : { remaining: 9 },
  );
  const credits = { tryConsume } as unknown as CreditsService;

  const add = vi.fn(async () => undefined);
  const queue = { add } as unknown as { add: typeof add };

  const svc = new AnalysisService(
    prisma,
    photos,
    credits,
    queue as never,
  );

  return { svc, prisma, photos, credits, queue, findFirst, create, add, tryConsume };
}

describe('AnalysisService (spec FR-S3-3)', () => {
  describe('requestReview', () => {
    it('404 PHOTO_NOT_FOUND khi photo không thuộc user (qua PhotosService.findOwned)', async () => {
      const { svc } = service({
        photoError: new AppError(404, 'PHOTO_NOT_FOUND', 'Photo not found'),
      });

      await expect(
        svc.requestReview('u-1', 'free', 10, PHOTO_ID),
      ).rejects.toMatchObject({ code: 'PHOTO_NOT_FOUND' });
    });

    it('422 PHOTO_NOT_UPLOADED khi storagePath null', async () => {
      const { svc } = service({
        photo: { id: PHOTO_ID, userId: 'u-1', storagePath: null },
      });

      await expect(
        svc.requestReview('u-1', 'free', 10, PHOTO_ID),
      ).rejects.toMatchObject({ code: 'PHOTO_NOT_UPLOADED' });

      await svc.requestReview('u-1', 'free', 10, PHOTO_ID).catch((err: AppError) => {
        expect(err.getStatus()).toBe(422);
      });
    });

    it('409 REVIEW_IN_PROGRESS khi đã có review queued/processing', async () => {
      const { svc } = service({ existingInProgress: { id: 'existing-analysis' } });

      await expect(
        svc.requestReview('u-1', 'free', 10, PHOTO_ID),
      ).rejects.toMatchObject({ code: 'REVIEW_IN_PROGRESS' });

      await svc.requestReview('u-1', 'free', 10, PHOTO_ID).catch((err: AppError) => {
        expect(err.getStatus()).toBe(409);
      });
    });

    it('402 CREDITS_EXHAUSTED khi tryConsume trả null', async () => {
      const { svc } = service({ consumeResult: null });

      await expect(
        svc.requestReview('u-1', 'free', 10, PHOTO_ID),
      ).rejects.toMatchObject({ code: 'CREDITS_EXHAUSTED' });

      await svc.requestReview('u-1', 'free', 10, PHOTO_ID).catch((err: AppError) => {
        expect(err.getStatus()).toBe(402);
      });
    });

    it('happy path: enqueue job + trả QUEUED + creditsRemaining', async () => {
      const { svc, create, add, tryConsume } = service({
        createdAnalysisId: 'analysis-42',
        consumeResult: { remaining: 7 },
      });

      const result = await svc.requestReview('u-1', 'free', 10, PHOTO_ID);

      expect(tryConsume).toHaveBeenCalledWith('u-1', 'free', 10);
      expect(create).toHaveBeenCalledWith(
        expect.objectContaining({
          data: expect.objectContaining({
            photoId: PHOTO_ID,
            kind: 'cloud',
            provider: 'pending',
            status: 'queued',
          }),
        }),
      );
      expect(add).toHaveBeenCalledWith(
        'review',
        { analysisId: 'analysis-42' },
        expect.objectContaining({ attempts: 3 }),
      );
      expect(result).toEqual({
        reviewId: 'analysis-42',
        status: 'QUEUED',
        creditsRemaining: 7,
      });
    });
  });

  describe('getReview', () => {
    it('404 REVIEW_NOT_FOUND khi chưa có cloud analysis nào', async () => {
      const { svc, prisma } = service();
      (prisma.analysis.findFirst as ReturnType<typeof vi.fn>).mockResolvedValueOnce(null);

      await expect(svc.getReview('u-1', PHOTO_ID)).rejects.toMatchObject({
        code: 'REVIEW_NOT_FOUND',
      });
    });

    it('trả scores/explanation/suggestions khi status done', async () => {
      const { svc, prisma } = service();
      (prisma.analysis.findFirst as ReturnType<typeof vi.fn>).mockResolvedValueOnce({
        id: 'analysis-1',
        status: 'done',
        provider: 'claude',
        createdAt: new Date('2026-07-06T10:00:00.000Z'),
        result: {
          scores: { composition: 90, lighting: 80, focus: 95, background: 70 },
          explanation: 'Tốt lắm',
          suggestions: ['Lùi lại 30cm'],
        },
      });

      const result = await svc.getReview('u-1', PHOTO_ID);

      expect(result).toEqual({
        reviewId: 'analysis-1',
        status: 'DONE',
        provider: 'claude',
        createdAt: new Date('2026-07-06T10:00:00.000Z'),
        scores: { composition: 90, lighting: 80, focus: 95, background: 70 },
        explanation: 'Tốt lắm',
        suggestions: ['Lùi lại 30cm'],
      });
    });

    it('không trả scores khi status queued (chưa done)', async () => {
      const { svc, prisma } = service();
      (prisma.analysis.findFirst as ReturnType<typeof vi.fn>).mockResolvedValueOnce({
        id: 'analysis-1',
        status: 'queued',
        provider: 'pending',
        createdAt: new Date('2026-07-06T10:00:00.000Z'),
        result: {},
      });

      const result = await svc.getReview('u-1', PHOTO_ID);

      expect(result).toEqual({
        reviewId: 'analysis-1',
        status: 'QUEUED',
        provider: 'pending',
        createdAt: new Date('2026-07-06T10:00:00.000Z'),
      });
    });
  });
});
