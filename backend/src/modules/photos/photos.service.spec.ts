import { describe, expect, it, vi } from 'vitest';

import { AppError } from '../../common/http/http-error.filter';
import { PrismaService } from '../../common/prisma/prisma.service';
import { PhotosService } from './photos.service';
import { StorageService } from './storage.service';

type PhotoRow = {
  id: string;
  userId: string;
  storagePath: string | null;
  sceneType: string | null;
  captureMeta: unknown;
  takenAt: Date;
};

function service(overrides?: { existing?: PhotoRow | null }) {
  const upsert = vi.fn(async () => undefined);
  const findUnique = vi.fn(async () => overrides?.existing ?? null);

  const prisma = {
    photo: { findUnique, upsert },
  } as unknown as PrismaService;

  const createUploadUrl = vi.fn(async () => ({
    uploadUrl: 'https://storage.googleapis.com/bucket/photos/u-1/p-1.jpg?sig=abc',
    expiresAt: new Date('2026-07-06T00:15:00.000Z'),
  }));
  const storage = { createUploadUrl } as unknown as StorageService;

  return { svc: new PhotosService(prisma, storage), prisma, storage, upsert, findUnique };
}

const PHOTO_ID = '11111111-1111-1111-1111-111111111111';

describe('PhotosService (spec FR-S3-2)', () => {
  describe('createUploadUrl', () => {
    it('từ chối content-type khác image/jpeg (400 UNSUPPORTED_CONTENT_TYPE)', async () => {
      const { svc } = service();

      await expect(
        svc.createUploadUrl('u-1', { photoId: PHOTO_ID, contentType: 'image/png' }),
      ).rejects.toMatchObject({ code: 'UNSUPPORTED_CONTENT_TYPE' });

      await svc
        .createUploadUrl('u-1', { photoId: PHOTO_ID, contentType: 'image/png' })
        .catch((err: AppError) => {
          expect(err.getStatus()).toBe(400);
        });
    });

    it('upsert Photo metadata + trả signed URL cho content-type hợp lệ', async () => {
      const { svc, upsert, storage } = service();

      const result = await svc.createUploadUrl('u-1', {
        photoId: PHOTO_ID,
        contentType: 'image/jpeg',
      });

      expect(upsert).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { id: PHOTO_ID },
          create: expect.objectContaining({
            id: PHOTO_ID,
            userId: 'u-1',
            storagePath: `photos/u-1/${PHOTO_ID}.jpg`,
          }),
          update: { storagePath: `photos/u-1/${PHOTO_ID}.jpg` },
        }),
      );
      expect(storage.createUploadUrl).toHaveBeenCalledWith(
        `photos/u-1/${PHOTO_ID}.jpg`,
        'image/jpeg',
      );
      expect(result).toEqual({
        uploadUrl: 'https://storage.googleapis.com/bucket/photos/u-1/p-1.jpg?sig=abc',
        storagePath: `photos/u-1/${PHOTO_ID}.jpg`,
        expiresAt: new Date('2026-07-06T00:15:00.000Z'),
      });
    });

    it('404 PHOTO_NOT_FOUND khi photoId đã tồn tại nhưng thuộc user khác', async () => {
      const existing: PhotoRow = {
        id: PHOTO_ID,
        userId: 'other-user',
        storagePath: null,
        sceneType: null,
        captureMeta: {},
        takenAt: new Date(),
      };
      const { svc } = service({ existing });

      await expect(
        svc.createUploadUrl('u-1', { photoId: PHOTO_ID, contentType: 'image/jpeg' }),
      ).rejects.toMatchObject({ code: 'PHOTO_NOT_FOUND' });

      await svc
        .createUploadUrl('u-1', { photoId: PHOTO_ID, contentType: 'image/jpeg' })
        .catch((err: AppError) => {
          expect(err.getStatus()).toBe(404);
        });
    });
  });

  describe('findOwned', () => {
    it('trả photo khi đúng chủ', async () => {
      const existing: PhotoRow = {
        id: PHOTO_ID,
        userId: 'u-1',
        storagePath: `photos/u-1/${PHOTO_ID}.jpg`,
        sceneType: 'portrait',
        captureMeta: {},
        takenAt: new Date(),
      };
      const { svc } = service({ existing });

      const result = await svc.findOwned('u-1', PHOTO_ID);

      expect(result.id).toBe(PHOTO_ID);
    });

    it('404 PHOTO_NOT_FOUND khi photo thuộc user khác', async () => {
      const existing: PhotoRow = {
        id: PHOTO_ID,
        userId: 'other-user',
        storagePath: null,
        sceneType: null,
        captureMeta: {},
        takenAt: new Date(),
      };
      const { svc } = service({ existing });

      await expect(svc.findOwned('u-1', PHOTO_ID)).rejects.toMatchObject({
        code: 'PHOTO_NOT_FOUND',
      });
    });

    it('404 PHOTO_NOT_FOUND khi photo không tồn tại', async () => {
      const { svc } = service({ existing: null });

      await expect(svc.findOwned('u-1', PHOTO_ID)).rejects.toMatchObject({
        code: 'PHOTO_NOT_FOUND',
      });
    });
  });
});
