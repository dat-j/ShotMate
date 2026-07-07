import { Body, Controller, Get, HttpCode, Post, Query } from '@nestjs/common';

import { AuthUser, CurrentUser } from '../../common/auth/current-user.decorator';
import { PullPhotosResult, SyncService } from '../sync/sync.service';
import { PullPhotosQueryDto } from './dto/pull-photos-query.dto';
import { UploadUrlDto } from './dto/upload-url.dto';
import { PhotosService, UploadUrlResult } from './photos.service';

const DEFAULT_PULL_LIMIT = 20;

/**
 * PhotosController — POST /photos/upload-url (spec FR-S3-2) + GET /photos
 * pull chiều về sync (spec FR-S3-6; route chuyển từ /sync/photos —
 * spec-sprint-4 FR-S4-5, trả nợ D3, đúng bảng API spec-sprint-3: route
 * literal `/photos` không va `/photos/:id/review`). Authenticated (guard global).
 */
@Controller('photos')
export class PhotosController {
  constructor(
    private readonly photos: PhotosService,
    private readonly sync: SyncService,
  ) {}

  @Post('upload-url')
  @HttpCode(201)
  createUploadUrl(
    @CurrentUser() user: AuthUser,
    @Body() dto: UploadUrlDto,
  ): Promise<UploadUrlResult> {
    return this.photos.createUploadUrl(user.userId, dto);
  }

  @Get()
  pull(
    @CurrentUser() user: AuthUser,
    @Query() query: PullPhotosQueryDto,
  ): Promise<PullPhotosResult> {
    return this.sync.pullPhotos(user.userId, query.cursor, query.limit ?? DEFAULT_PULL_LIMIT);
  }
}
