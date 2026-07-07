import { Module } from '@nestjs/common';

import { SyncModule } from '../sync/sync.module';
import { PhotosController } from './photos.controller';
import { PhotosService } from './photos.service';
import { StorageService } from './storage.service';

/**
 * PhotosModule — photo metadata + signed URL upload GCS (spec FR-S3-2,
 * ADR-0002) + GET /photos pull chiều về sync (spec-sprint-4 FR-S4-5, trả nợ
 * D3 — dùng SyncService của SyncModule, không trùng logic). Exports
 * PhotosService + StorageService: AnalysisModule needs PhotosService
 * (ownership check) and StorageService (download image for the review worker).
 *
 * KHÔNG import `ConfigModule` (chỉ token, không `.forRoot()`) — làm vậy che
 * mất `ConfigService` global thật bằng 1 module rỗng cùng tên (đã tự gây lỗi
 * này khi debug spec-sprint-4 D7, revert lại). `ConfigModule.forRoot({isGlobal:true})`
 * ở AppModule đã đủ cho mọi module con.
 */
@Module({
  imports: [SyncModule],
  controllers: [PhotosController],
  providers: [PhotosService, StorageService],
  exports: [PhotosService, StorageService],
})
export class PhotosModule {}
