import { randomUUID } from 'node:crypto';

import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';

import { generateToken, hashToken } from '../../common/crypto/token.util';
import { AppError } from '../../common/http/http-error.filter';
import { PrismaService } from '../../common/prisma/prisma.service';
import { MailerService } from './mailer.service';

export interface TokenPair {
  accessToken: string;
  refreshToken: string;
}

export interface VerifyResult extends TokenPair {
  user: {
    id: string;
    email: string;
    displayName: string | null;
  };
}

/**
 * AuthService — magic link + JWT rotation (spec FR-S3-1, Rule 6, EC-S3-4,
 * EC-S3-5). Mọi token lưu SHA-256 hash — raw chỉ tồn tại ở mail/client.
 */
@Injectable()
export class AuthService {
  private readonly logger = new Logger(AuthService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly jwt: JwtService,
    private readonly mailer: MailerService,
    private readonly config: ConfigService,
  ) {}

  /**
   * Tạo + gửi magic link. Luôn "thành công" bất kể email tồn tại hay không
   * (controller trả 202 vô điều kiện — spec Rule 6, chống oracle user tồn tại).
   */
  async requestMagicLink(email: string): Promise<void> {
    const token = generateToken();
    const ttlMinutes = this.config.get<number>('MAGIC_LINK_TTL_MINUTES') ?? 10;
    const expiresAt = new Date(Date.now() + ttlMinutes * 60 * 1000);

    await this.prisma.magicLinkToken.create({
      data: {
        email,
        tokenHash: hashToken(token),
        expiresAt,
      },
    });

    await this.mailer.sendMagicLink(email, token);
  }

  /**
   * Verify magic link token (single-use). Sai/hết hạn/đã dùng đều trả CÙNG
   * một lỗi AUTH_LINK_INVALID (spec: "một code, không phân biệt để tránh
   * oracle" — EC-S3-4 mở trên thiết bị khác vẫn login được vì token không
   * bind device).
   */
  async verify(token: string): Promise<VerifyResult> {
    const record = await this.prisma.magicLinkToken.findUnique({
      where: { tokenHash: hashToken(token) },
    });

    if (!record || record.usedAt !== null || record.expiresAt.getTime() < Date.now()) {
      throw new AppError(401, 'AUTH_LINK_INVALID', 'Magic link không hợp lệ hoặc đã hết hạn');
    }

    await this.prisma.magicLinkToken.update({
      where: { id: record.id },
      data: { usedAt: new Date() },
    });

    const user = await this.prisma.user.upsert({
      where: { email: record.email },
      create: { email: record.email },
      update: {},
    });

    const pair = await this.issueTokenPair(user.id);

    return {
      ...pair,
      user: {
        id: user.id,
        email: user.email,
        displayName: user.displayName,
      },
    };
  }

  /**
   * Refresh rotation + reuse detection (spec Rule 6, EC-S3-5). Refresh token
   * cũ dùng lại (đã revoked trước đó) → revoke CẢ family, buộc login lại.
   */
  async refresh(refreshToken: string): Promise<TokenPair> {
    const record = await this.prisma.refreshToken.findUnique({
      where: { tokenHash: hashToken(refreshToken) },
    });

    if (!record) {
      throw new AppError(401, 'AUTH_TOKEN_INVALID', 'Refresh token không hợp lệ');
    }

    if (record.revokedAt !== null) {
      await this.prisma.refreshToken.updateMany({
        where: { familyId: record.familyId, revokedAt: null },
        data: { revokedAt: new Date() },
      });
      this.logger.warn(
        `Refresh token reuse detected — family ${record.familyId} revoked (userId=${record.userId})`,
      );
      throw new AppError(401, 'AUTH_TOKEN_REUSED', 'Refresh token đã bị sử dụng lại — vui lòng đăng nhập lại');
    }

    if (record.expiresAt.getTime() < Date.now()) {
      throw new AppError(401, 'AUTH_TOKEN_INVALID', 'Refresh token đã hết hạn');
    }

    await this.prisma.refreshToken.update({
      where: { id: record.id },
      data: { revokedAt: new Date() },
    });

    return this.issueTokenPair(record.userId, record.familyId);
  }

  /**
   * Sinh cặp access/refresh token mới. Access = JWT { sub, plan } (plan mặc
   * định 'free' — chỉ để hint UI, authorization thật luôn query DB, spec
   * FR-S3-1). Refresh = opaque random token, lưu hash, rotation trong cùng
   * familyId (mới nếu chưa có — login lần đầu).
   */
  private async issueTokenPair(userId: string, familyId?: string): Promise<TokenPair> {
    const accessToken = await this.jwt.signAsync({ sub: userId, plan: 'free' });

    const rawRefreshToken = generateToken();
    const refreshTtlDays = this.config.get<number>('JWT_REFRESH_TTL_DAYS') ?? 30;
    const expiresAt = new Date(Date.now() + refreshTtlDays * 24 * 60 * 60 * 1000);

    await this.prisma.refreshToken.create({
      data: {
        userId,
        familyId: familyId ?? randomUUID(),
        tokenHash: hashToken(rawRefreshToken),
        expiresAt,
      },
    });

    return { accessToken, refreshToken: rawRefreshToken };
  }
}
