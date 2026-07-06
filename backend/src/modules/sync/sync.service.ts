import { Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';

import { AppError } from '../../common/http/http-error.filter';
import { PrismaService } from '../../common/prisma/prisma.service';
import { AnalysisSyncDto, PhotoSyncDto, ScoreSyncDto, SyncDto } from './dto/sync.dto';

const MAX_BATCH_RECORDS = 500;

export interface SyncConflict {
  id: string;
  reason: string;
}

export interface SyncResult {
  accepted: number;
  conflicts: SyncConflict[];
}

export interface PullPhotoItem {
  id: string;
  storagePath: string | null;
  sceneType: string | null;
  captureMeta: unknown;
  takenAt: string;
}

export interface PullPhotosResult {
  items: PullPhotoItem[];
  nextCursor?: string;
}

type Tx = Prisma.TransactionClient;

/**
 * SyncService — sync đa thiết bị (spec FR-S3-6, Rule 5). UUID client thắng
 * (ADR-0002, server không bao giờ cấp lại id), last-write-wins theo taken_at
 * cho photo (EC-S3-6). Batch tối đa 500 record TỔNG (photos+analyses+scores).
 */
@Injectable()
export class SyncService {
  constructor(private readonly prisma: PrismaService) {}

  async sync(userId: string, dto: SyncDto): Promise<SyncResult> {
    const totalRecords = dto.photos.length + dto.analyses.length + dto.scores.length;
    if (totalRecords > MAX_BATCH_RECORDS) {
      throw new AppError(
        400,
        'BATCH_TOO_LARGE',
        `Batch has ${totalRecords} records, max ${MAX_BATCH_RECORDS}`,
      );
    }

    return this.prisma.$transaction(async (tx) => {
      const conflicts: SyncConflict[] = [];
      let accepted = 0;

      for (const photo of dto.photos) {
        const outcome = await this.upsertPhoto(tx, userId, photo);
        if (outcome.conflict) {
          conflicts.push(outcome.conflict);
        } else {
          accepted += 1;
        }
      }

      for (const analysis of dto.analyses) {
        const outcome = await this.upsertAnalysis(tx, userId, analysis);
        if (outcome.conflict) {
          conflicts.push(outcome.conflict);
        } else {
          accepted += 1;
        }
      }

      for (const score of dto.scores) {
        const outcome = await this.upsertScore(tx, userId, score);
        if (outcome.conflict) {
          conflicts.push(outcome.conflict);
        } else {
          accepted += 1;
        }
      }

      return { accepted, conflicts };
    });
  }

  async pullPhotos(
    userId: string,
    cursor: string | undefined,
    limit: number,
  ): Promise<PullPhotosResult> {
    const rows = await this.prisma.photo.findMany({
      where: {
        userId,
        ...(cursor ? { takenAt: { lt: new Date(cursor) } } : {}),
      },
      orderBy: { takenAt: 'desc' },
      take: limit + 1,
    });

    const hasMore = rows.length > limit;
    const page = hasMore ? rows.slice(0, limit) : rows;
    const lastItem = page.at(-1);

    return {
      items: page.map((row) => ({
        id: row.id,
        storagePath: row.storagePath,
        sceneType: row.sceneType,
        captureMeta: row.captureMeta,
        takenAt: row.takenAt.toISOString(),
      })),
      ...(hasMore && lastItem ? { nextCursor: lastItem.takenAt.toISOString() } : {}),
    };
  }

  /**
   * Upsert photo theo id (Rule 5). Nếu id đã tồn tại nhưng thuộc user khác →
   * conflict, KHÔNG ghi đè (an ninh — chống chiếm id của user khác). Nếu
   * cùng chủ nhưng taken_at cũ hơn bản đã lưu → conflict LWW, giữ bản server.
   *
   * SECURITY (CWE-639): sync KHÔNG BAO GIỜ nhận `storagePath` do client gửi.
   * storagePath là con trỏ tới pixel trong bucket, chỉ được server sinh ở
   * PhotosService.createUploadUrl (`photos/{userId}/{photoId}.jpg`). Nếu tin
   * client, attacker có thể trỏ photo của mình sang ảnh của user khác rồi
   * gọi review → đọc trộm ảnh riêng tư. Sync chỉ đồng bộ metadata (Rule 4:
   * "không bao giờ đẩy pixel") — giữ nguyên storagePath phía server.
   */
  private async upsertPhoto(
    tx: Tx,
    userId: string,
    dto: PhotoSyncDto,
  ): Promise<{ conflict?: SyncConflict }> {
    const takenAt = this.toDate(dto.takenAt);
    const existing = await tx.photo.findUnique({ where: { id: dto.id } });

    if (existing && existing.userId !== userId) {
      return { conflict: { id: dto.id, reason: 'owned_by_other_user' } };
    }

    if (existing && existing.takenAt.getTime() > takenAt.getTime()) {
      return { conflict: { id: dto.id, reason: 'stale_taken_at' } };
    }

    await tx.photo.upsert({
      where: { id: dto.id },
      create: {
        id: dto.id,
        userId,
        // storagePath KHÔNG lấy từ client — photo mới sync chỉ có metadata,
        // pixel (nếu có) được server gán qua upload-url flow riêng.
        storagePath: null,
        sceneType: dto.sceneType ?? null,
        captureMeta: dto.captureMeta as Prisma.InputJsonValue,
        takenAt,
      },
      update: {
        // KHÔNG đụng storagePath khi update — giữ giá trị server đã có.
        sceneType: dto.sceneType ?? null,
        captureMeta: dto.captureMeta as Prisma.InputJsonValue,
        takenAt,
      },
    });

    return {};
  }

  /**
   * Analysis là con của Photo thuộc user — chỉ upsert nếu photo cha thuộc
   * đúng user (đã pass ở bước photos hoặc pre-existing). LWW theo createdAt.
   */
  private async upsertAnalysis(
    tx: Tx,
    userId: string,
    dto: AnalysisSyncDto,
  ): Promise<{ conflict?: SyncConflict }> {
    const photo = await tx.photo.findUnique({ where: { id: dto.photoId } });
    if (!photo || photo.userId !== userId) {
      return { conflict: { id: dto.id, reason: 'photo_not_owned' } };
    }

    const createdAt = this.toDate(dto.createdAt);
    const existing = await tx.analysis.findUnique({ where: { id: dto.id } });

    if (existing && existing.photoId !== dto.photoId) {
      return { conflict: { id: dto.id, reason: 'owned_by_other_user' } };
    }

    if (existing && existing.createdAt.getTime() > createdAt.getTime()) {
      return { conflict: { id: dto.id, reason: 'stale_taken_at' } };
    }

    await tx.analysis.upsert({
      where: { id: dto.id },
      create: {
        id: dto.id,
        photoId: dto.photoId,
        kind: dto.kind,
        provider: dto.provider,
        status: dto.status,
        result: dto.result as Prisma.InputJsonValue,
        createdAt,
      },
      update: {
        kind: dto.kind,
        provider: dto.provider,
        status: dto.status,
        result: dto.result as Prisma.InputJsonValue,
      },
    });

    return {};
  }

  /** Score là con 1-1 của Analysis — không có timestamp riêng, upsert theo id nếu analysis cha hợp lệ. */
  private async upsertScore(
    tx: Tx,
    userId: string,
    dto: ScoreSyncDto,
  ): Promise<{ conflict?: SyncConflict }> {
    const analysis = await tx.analysis.findUnique({
      where: { id: dto.analysisId },
      include: { photo: true },
    });
    if (!analysis || analysis.photo.userId !== userId) {
      return { conflict: { id: dto.id, reason: 'analysis_not_owned' } };
    }

    const existing = await tx.score.findUnique({ where: { id: dto.id } });
    if (existing && existing.analysisId !== dto.analysisId) {
      return { conflict: { id: dto.id, reason: 'owned_by_other_user' } };
    }

    await tx.score.upsert({
      where: { id: dto.id },
      create: {
        id: dto.id,
        analysisId: dto.analysisId,
        composition: dto.composition,
        lighting: dto.lighting,
        focus: dto.focus,
        background: dto.background,
      },
      update: {
        composition: dto.composition,
        lighting: dto.lighting,
        focus: dto.focus,
        background: dto.background,
      },
    });

    return {};
  }

  private toDate(value: number | string): Date {
    return typeof value === 'number' ? new Date(value) : new Date(value);
  }
}
