import { Body, Controller, HttpCode, Post } from '@nestjs/common';

import { AuthUser, CurrentUser } from '../../common/auth/current-user.decorator';
import { UploadUrlDto } from './dto/upload-url.dto';
import { PhotosService, UploadUrlResult } from './photos.service';

/** PhotosController — POST /photos/upload-url (spec FR-S3-2). Authenticated (guard global). */
@Controller('photos')
export class PhotosController {
  constructor(private readonly photos: PhotosService) {}

  @Post('upload-url')
  @HttpCode(201)
  createUploadUrl(
    @CurrentUser() user: AuthUser,
    @Body() dto: UploadUrlDto,
  ): Promise<UploadUrlResult> {
    return this.photos.createUploadUrl(user.userId, dto);
  }
}
