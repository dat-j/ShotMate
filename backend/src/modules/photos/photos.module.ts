import { Module } from '@nestjs/common';

import { PhotosController } from './photos.controller';
import { PhotosService } from './photos.service';
import { StorageService } from './storage.service';

/**
 * PhotosModule — photo metadata + signed URL upload GCS (spec FR-S3-2,
 * ADR-0002). Exports PhotosService + StorageService: AnalysisModule needs
 * PhotosService (ownership check) and StorageService (download image for
 * the review worker).
 */
@Module({
  controllers: [PhotosController],
  providers: [PhotosService, StorageService],
  exports: [PhotosService, StorageService],
})
export class PhotosModule {}
