import { Module } from '@nestjs/common';

import { CreditsModule } from '../credits/credits.module';
import { PhotosModule } from '../photos/photos.module';
import { SubscriptionsService } from '../subscriptions/subscriptions.service';
import { UsersController } from './users.controller';
import { UsersService } from './users.service';

/**
 * UsersModule — account management (spec FR-S3-7): GET/DELETE /me.
 *
 * SubscriptionsService được khai báo local (thay vì import SubscriptionsModule)
 * để tránh đụng độ với worker khác đang implement subscriptions.module.ts —
 * service này chỉ phụ thuộc PrismaService (global) nên an toàn khi tái tạo
 * provider ở đây. PhotosModule import để lấy StorageService (xoá ảnh GCS khi
 * xoá account — EC-S3-11).
 */
@Module({
  imports: [CreditsModule, PhotosModule],
  controllers: [UsersController],
  providers: [UsersService, SubscriptionsService],
})
export class UsersModule {}
