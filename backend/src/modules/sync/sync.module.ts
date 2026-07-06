import { Module } from '@nestjs/common';

import { SyncController } from './sync.controller';
import { SyncService } from './sync.service';

/**
 * SyncModule — implement Sprint 3 (spec FR-S3-6). POST /sync (LWW theo
 * taken_at), GET /sync/photos pull. Cắt đầu tiên nếu trễ (spec Rule 10).
 */
@Module({
  controllers: [SyncController],
  providers: [SyncService],
})
export class SyncModule {}
