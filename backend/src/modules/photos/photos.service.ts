import { Injectable } from '@nestjs/common';
import { Prisma, Photo } from '@prisma/client';

import { AppError } from '../../common/http/http-error.filter';
import { PrismaService } from '../../common/prisma/prisma.service';
import { UploadUrlDto } from './dto/upload-url.dto';
import { StorageService } from './storage.service';

const SUPPORTED_CONTENT_TYPE = 'image/jpeg';

export interface UploadUrlResult {
  uploadUrl: string;
  storagePath: string;
  expiresAt: Date;
}

/**
 * PhotosService — photo metadata + signed upload URL (spec FR-S3-2).
 *
 * Object path is ALWAYS server-generated (`photos/{userId}/{photoId}.jpg`) —
 * client never controls the storage path (spec Security: chống traversal/overwrite).
 * Ownership is always scoped by userId from JWT; a photo owned by another
 * user is reported as 404 (not 403) to avoid leaking existence (spec Security).
 */
@Injectable()
export class PhotosService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly storage: StorageService,
  ) {}

  async createUploadUrl(userId: string, dto: UploadUrlDto): Promise<UploadUrlResult> {
    if (dto.contentType !== SUPPORTED_CONTENT_TYPE) {
      throw new AppError(
        400,
        'UNSUPPORTED_CONTENT_TYPE',
        `Chỉ chấp nhận ${SUPPORTED_CONTENT_TYPE}, nhận được ${dto.contentType}`,
      );
    }

    const existing = await this.prisma.photo.findUnique({ where: { id: dto.photoId } });
    if (existing && existing.userId !== userId) {
      // Không lộ sự tồn tại của photo user khác (spec Security).
      throw new AppError(404, 'PHOTO_NOT_FOUND', 'Photo not found');
    }

    const objectPath = `photos/${userId}/${dto.photoId}.jpg`;

    await this.prisma.photo.upsert({
      where: { id: dto.photoId },
      create: {
        id: dto.photoId,
        userId,
        storagePath: objectPath,
        sceneType: existing?.sceneType ?? null,
        captureMeta: (existing?.captureMeta as Prisma.InputJsonValue) ?? {},
        takenAt: existing?.takenAt ?? new Date(),
      },
      update: {
        storagePath: objectPath,
      },
    });

    const { uploadUrl, expiresAt } = await this.storage.createUploadUrl(
      objectPath,
      dto.contentType,
    );

    return { uploadUrl, storagePath: objectPath, expiresAt };
  }

  /** Tra cứu photo thuộc đúng userId — 404 nếu không tồn tại hoặc không phải chủ (Security). */
  async findOwned(userId: string, photoId: string): Promise<Photo> {
    const photo = await this.prisma.photo.findUnique({ where: { id: photoId } });
    if (!photo || photo.userId !== userId) {
      throw new AppError(404, 'PHOTO_NOT_FOUND', 'Photo not found');
    }
    return photo;
  }
}
