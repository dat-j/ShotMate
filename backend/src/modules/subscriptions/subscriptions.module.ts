import { Module } from '@nestjs/common';

import { SubscriptionsController } from './subscriptions.controller';
import { SubscriptionsService } from './subscriptions.service';

/**
 * SubscriptionsModule — webhook RevenueCat + verify fallback (spec FR-S3-5).
 * Exports SubscriptionsService — reused by UsersModule (/me) declared locally
 * there to avoid coupling across parallel workers (see users.module.ts).
 */
@Module({
  controllers: [SubscriptionsController],
  providers: [SubscriptionsService],
  exports: [SubscriptionsService],
})
export class SubscriptionsModule {}
