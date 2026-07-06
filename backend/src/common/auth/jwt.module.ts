import { Global, Module } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtModule } from '@nestjs/jwt';

import { JwtAuthGuard } from './jwt-auth.guard';

/**
 * Global JWT setup — secret + access TTL từ env. RefreshToken KHÔNG dùng
 * JwtService (lưu random opaque hash trong DB, spec Rule 6) — chỉ access
 * token là JWT ký ở đây.
 */
@Global()
@Module({
  imports: [
    JwtModule.registerAsync({
      inject: [ConfigService],
      useFactory: (config: ConfigService) => ({
        secret: config.getOrThrow<string>('JWT_SECRET'),
        signOptions: {
          // jsonwebtoken chấp nhận '15m'/'7d'; typing dùng template literal
          // hẹp nên cast từ env string.
          expiresIn: (config.get<string>('JWT_ACCESS_TTL') ??
            '15m') as `${number}${'m' | 'h' | 'd'}`,
        },
      }),
    }),
  ],
  providers: [JwtAuthGuard],
  exports: [JwtModule, JwtAuthGuard],
})
export class AppJwtModule {}
