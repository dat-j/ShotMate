import { Body, Controller, Get, HttpCode, Post, Query } from '@nestjs/common';

import { AuthUser, CurrentUser } from '../../common/auth/current-user.decorator';
import { PullPhotosQueryDto } from './dto/pull-photos-query.dto';
import { SyncDto } from './dto/sync.dto';
import { PullPhotosResult, SyncResult, SyncService } from './sync.service';

const DEFAULT_PULL_LIMIT = 20;

/**
 * SyncController — sync đa thiết bị (spec FR-S3-6). Tất cả route
 * authenticated (JwtAuthGuard global) — userId luôn từ @CurrentUser().
 *
 * NOTE: pull lives under /sync/photos to avoid collision with
 * PhotosController (owned by another worker) which also exposes /photos.
 */
@Controller('sync')
export class SyncController {
  constructor(private readonly sync: SyncService) {}

  @Post()
  @HttpCode(200)
  push(@CurrentUser() user: AuthUser, @Body() dto: SyncDto): Promise<SyncResult> {
    return this.sync.sync(user.userId, dto);
  }

  @Get('photos')
  pull(
    @CurrentUser() user: AuthUser,
    @Query() query: PullPhotosQueryDto,
  ): Promise<PullPhotosResult> {
    return this.sync.pullPhotos(user.userId, query.cursor, query.limit ?? DEFAULT_PULL_LIMIT);
  }
}
