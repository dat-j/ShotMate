import { Body, Controller, HttpCode, Post } from '@nestjs/common';

import { AuthUser, CurrentUser } from '../../common/auth/current-user.decorator';
import { SyncDto } from './dto/sync.dto';
import { SyncResult, SyncService } from './sync.service';

/**
 * SyncController — sync đa thiết bị, chiều push (spec FR-S3-6, Rule 5).
 * Authenticated (JwtAuthGuard global) — userId luôn từ @CurrentUser().
 *
 * Pull chiều về đã chuyển sang `GET /photos` (PhotosController) — spec-sprint-4
 * FR-S4-5, trả nợ D3.
 */
@Controller('sync')
export class SyncController {
  constructor(private readonly sync: SyncService) {}

  @Post()
  @HttpCode(200)
  push(@CurrentUser() user: AuthUser, @Body() dto: SyncDto): Promise<SyncResult> {
    return this.sync.sync(user.userId, dto);
  }
}
