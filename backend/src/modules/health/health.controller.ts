import { Controller, Get } from '@nestjs/common';

import { Public } from '../../common/auth/public.decorator';

/** Health check cho Cloud Run (spec FR-S3-8) — public, không auth. */
@Controller('healthz')
export class HealthController {
  @Public()
  @Get()
  check(): { status: string } {
    return { status: 'ok' };
  }
}
