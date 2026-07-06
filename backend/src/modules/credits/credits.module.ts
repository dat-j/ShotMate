import { Module } from '@nestjs/common';

import { CreditsService } from './credits.service';

/**
 * CreditsModule — enforce 10 review/ngày free, unlimited premium (spec
 * FR-S3-4). Export CreditsService cho Users (/me) + Analysis (trừ/hoàn).
 */
@Module({
  providers: [CreditsService],
  exports: [CreditsService],
})
export class CreditsModule {}
