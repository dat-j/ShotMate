import { Body, Controller, HttpCode, Post } from '@nestjs/common';

import { Public } from '../../common/auth/public.decorator';
import { RateLimit } from '../../common/rate-limit/rate-limit.decorator';
import { AuthService, TokenPair, VerifyResult } from './auth.service';
import { MagicLinkDto } from './dto/magic-link.dto';
import { RefreshDto } from './dto/refresh.dto';
import { VerifyDto } from './dto/verify.dto';

/**
 * AuthController — magic link + JWT (spec FR-S3-1). 3 route public, bỏ qua
 * JwtAuthGuard global.
 */
@Controller('auth')
export class AuthController {
  constructor(private readonly auth: AuthService) {}

  @Public()
  // FR-S4-4: cả 2 điều kiện đều áp dụng — 3/email/15 phút VÀ 10/IP/giờ.
  @RateLimit(
    { name: 'magic-link-email', limit: 3, windowSeconds: 15 * 60, keyBy: 'email' },
    { name: 'magic-link-ip', limit: 10, windowSeconds: 60 * 60, keyBy: 'ip' },
  )
  @Post('magic-link')
  @HttpCode(202)
  async requestMagicLink(@Body() dto: MagicLinkDto): Promise<Record<string, never>> {
    await this.auth.requestMagicLink(dto.email);
    return {};
  }

  @Public()
  @Post('verify')
  @HttpCode(200)
  verify(@Body() dto: VerifyDto): Promise<VerifyResult> {
    return this.auth.verify(dto.token);
  }

  @Public()
  @Post('refresh')
  @HttpCode(200)
  refresh(@Body() dto: RefreshDto): Promise<TokenPair> {
    return this.auth.refresh(dto.refreshToken);
  }
}
