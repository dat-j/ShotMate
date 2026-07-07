import { Module } from '@nestjs/common';

import { SyncController } from './sync.controller';
import { SyncService } from './sync.service';

/**
 * SyncModule — implement Sprint 3 (spec FR-S3-6). POST /sync (push, LWW theo
 * taken_at). Cắt đầu tiên nếu trễ (spec Rule 10).
 *
 * Pull chiều về (`GET /photos?cursor&limit`) sống ở PhotosController
 * (spec-sprint-4 FR-S4-5, trả nợ D3 — route literal `/photos` không va
 * `/photos/:id/review`, đúng bảng API spec-sprint-3). SyncService export ra
 * đây để PhotosModule dùng `pullPhotos` mà không trùng logic.
 */
@Module({
  controllers: [SyncController],
  providers: [SyncService],
  exports: [SyncService],
})
export class SyncModule {}
