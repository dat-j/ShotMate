import { Module } from '@nestjs/common';

import { AuthController } from './auth.controller';
import { AuthService } from './auth.service';
import { MailerService } from './mailer.service';

/**
 * AuthModule — magic link + JWT (access 15m / refresh 30d rotation),
 * spec FR-S3-1, Rule 6. PrismaModule + AppJwtModule đã global, không cần
 * import thêm. Xem docs/design/system-design-shotmate.md §3, §5.
 */
@Module({
  controllers: [AuthController],
  providers: [AuthService, MailerService],
})
export class AuthModule {}
