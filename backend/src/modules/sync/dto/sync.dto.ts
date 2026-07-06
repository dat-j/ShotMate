import { Type } from 'class-transformer';
import {
  ArrayMaxSize,
  IsArray,
  IsIn,
  IsInt,
  IsNumber,
  IsObject,
  IsOptional,
  IsString,
  IsUUID,
  ValidateNested,
} from 'class-validator';

/**
 * DTO cho POST /sync (spec FR-S3-6, Rule 5). UUID sinh tại client
 * (ADR-0002) — server upsert theo id, không bao giờ cấp lại id.
 * Batch cap 500 record TỔNG (photos+analyses+scores) enforced ở service
 * (SyncService.sync) vì cần cộng dồn cả 3 mảng.
 */

export class PhotoSyncDto {
  @IsUUID()
  id!: string;

  // storagePath CỐ TÌNH không có ở đây (SECURITY, CWE-639): con trỏ pixel chỉ
  // do server sinh (PhotosService.createUploadUrl). ValidationPipe
  // forbidNonWhitelisted → client gửi storagePath sẽ bị reject 400.

  @IsOptional()
  @IsString()
  sceneType?: string;

  @IsObject()
  captureMeta!: Record<string, unknown>;

  /** epoch ms hoặc ISO string — service chuẩn hoá ra Date. */
  @IsNumber()
  takenAt!: number;
}

export class AnalysisSyncDto {
  @IsUUID()
  id!: string;

  @IsUUID()
  photoId!: string;

  @IsIn(['on_device', 'cloud'])
  kind!: string;

  @IsString()
  provider!: string;

  @IsIn(['queued', 'processing', 'done', 'failed'])
  status!: string;

  @IsObject()
  result!: Record<string, unknown>;

  @IsNumber()
  createdAt!: number;
}

export class ScoreSyncDto {
  @IsUUID()
  id!: string;

  @IsUUID()
  analysisId!: string;

  @IsInt()
  composition!: number;

  @IsInt()
  lighting!: number;

  @IsInt()
  focus!: number;

  @IsInt()
  background!: number;
}

export class SyncDto {
  @IsArray()
  @ArrayMaxSize(500)
  @ValidateNested({ each: true })
  @Type(() => PhotoSyncDto)
  photos!: PhotoSyncDto[];

  @IsArray()
  @ArrayMaxSize(500)
  @ValidateNested({ each: true })
  @Type(() => AnalysisSyncDto)
  analyses!: AnalysisSyncDto[];

  @IsArray()
  @ArrayMaxSize(500)
  @ValidateNested({ each: true })
  @Type(() => ScoreSyncDto)
  scores!: ScoreSyncDto[];
}
