import { describe, expect, it, vi } from 'vitest';

import { PrismaService } from '../../common/prisma/prisma.service';
import { PhotoSyncDto, SyncDto } from './dto/sync.dto';
import { SyncService } from './sync.service';

function emptyDto(overrides?: Partial<SyncDto>): SyncDto {
  return {
    photos: [],
    analyses: [],
    scores: [],
    ...overrides,
  };
}

function photoDto(overrides?: Partial<PhotoSyncDto>): PhotoSyncDto {
  return {
    id: 'photo-1',
    captureMeta: { zoom: 1 },
    takenAt: Date.now(),
    ...overrides,
  };
}

function service(txOverrides?: {
  photoFindUnique?: unknown;
  analysisFindUnique?: unknown;
  scoreFindUnique?: unknown;
}) {
  const tx = {
    photo: {
      findUnique: vi.fn(async () => txOverrides?.photoFindUnique ?? null),
      upsert: vi.fn(async () => undefined),
      findMany: vi.fn(async () => []),
    },
    analysis: {
      findUnique: vi.fn(async () => txOverrides?.analysisFindUnique ?? null),
      upsert: vi.fn(async () => undefined),
    },
    score: {
      findUnique: vi.fn(async () => txOverrides?.scoreFindUnique ?? null),
      upsert: vi.fn(async () => undefined),
    },
  };

  const prisma = {
    $transaction: vi.fn(async (cb: (tx: typeof tx) => unknown) => cb(tx)),
    photo: tx.photo,
  } as unknown as PrismaService;

  return { svc: new SyncService(prisma), prisma, tx };
}

describe('SyncService (spec FR-S3-6, Rule 5)', () => {
  describe('sync — batch size', () => {
    it('rejects >500 records tổng với BATCH_TOO_LARGE', async () => {
      const { svc } = service();
      const photos = Array.from({ length: 501 }, (_, i) => photoDto({ id: `p-${i}` }));

      await expect(svc.sync('u-1', emptyDto({ photos }))).rejects.toMatchObject({
        code: 'BATCH_TOO_LARGE',
      });
    });

    it('accepts đúng 500 records tổng (biên)', async () => {
      const { svc } = service();
      const photos = Array.from({ length: 500 }, (_, i) => photoDto({ id: `p-${i}` }));

      const result = await svc.sync('u-1', emptyDto({ photos }));

      expect(result.accepted).toBe(500);
      expect(result.conflicts).toEqual([]);
    });
  });

  describe('sync — LWW theo taken_at (EC-S3-6)', () => {
    it('ghi đè khi incoming taken_at mới hơn bản đã lưu', async () => {
      const older = Date.now() - 10_000;
      const newer = Date.now();
      const { svc, tx } = service({
        photoFindUnique: { id: 'photo-1', userId: 'u-1', takenAt: new Date(older) },
      });

      const result = await svc.sync(
        'u-1',
        emptyDto({ photos: [photoDto({ id: 'photo-1', takenAt: newer })] }),
      );

      expect(result.accepted).toBe(1);
      expect(result.conflicts).toEqual([]);
      expect(tx.photo.upsert).toHaveBeenCalled();
    });

    it('giữ bản server khi incoming taken_at cũ hơn — trả conflict, không ghi đè', async () => {
      const newer = Date.now();
      const older = Date.now() - 10_000;
      const { svc, tx } = service({
        photoFindUnique: { id: 'photo-1', userId: 'u-1', takenAt: new Date(newer) },
      });

      const result = await svc.sync(
        'u-1',
        emptyDto({ photos: [photoDto({ id: 'photo-1', takenAt: older })] }),
      );

      expect(result.accepted).toBe(0);
      expect(result.conflicts).toEqual([{ id: 'photo-1', reason: 'stale_taken_at' }]);
      expect(tx.photo.upsert).not.toHaveBeenCalled();
    });
  });

  describe('sync — ownership (EC-S3-6, security)', () => {
    it('photo id thuộc user khác → conflict, không ghi đè', async () => {
      const { svc, tx } = service({
        photoFindUnique: { id: 'photo-1', userId: 'other-user', takenAt: new Date() },
      });

      const result = await svc.sync('u-1', emptyDto({ photos: [photoDto({ id: 'photo-1' })] }));

      expect(result.accepted).toBe(0);
      expect(result.conflicts).toEqual([{ id: 'photo-1', reason: 'owned_by_other_user' }]);
      expect(tx.photo.upsert).not.toHaveBeenCalled();
    });

    it('photo mới (chưa tồn tại) → accepted, upsert được gọi', async () => {
      const { svc, tx } = service({ photoFindUnique: null });

      const result = await svc.sync('u-1', emptyDto({ photos: [photoDto({ id: 'photo-new' })] }));

      expect(result.accepted).toBe(1);
      expect(tx.photo.upsert).toHaveBeenCalledWith(
        expect.objectContaining({ where: { id: 'photo-new' } }),
      );
    });

    it('KHÔNG ghi storagePath do client gửi (CWE-639 — chống đọc trộm ảnh user khác)', async () => {
      const { svc, tx } = service({ photoFindUnique: null });

      // Client cố nhồi storagePath trỏ tới ảnh của victim. DTO đã whitelist
      // bỏ field này, nhưng dù có lọt tới service, create luôn set null.
      const malicious = {
        ...photoDto({ id: 'photo-new' }),
        storagePath: 'photos/victim-user/secret.jpg',
      } as PhotoSyncDto;

      await svc.sync('u-1', emptyDto({ photos: [malicious] }));

      const createArg = tx.photo.upsert.mock.calls[0]?.[0] as {
        create: { storagePath: unknown };
      };
      expect(createArg.create.storagePath).toBeNull();
    });
  });

  describe('pullPhotos', () => {
    it('trả items rỗng + không nextCursor khi không có dữ liệu', async () => {
      const { svc } = service();

      const result = await svc.pullPhotos('u-1', undefined, 20);

      expect(result).toEqual({ items: [] });
    });
  });
});
