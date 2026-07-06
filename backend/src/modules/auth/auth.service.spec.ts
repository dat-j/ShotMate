import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { describe, expect, it, vi } from 'vitest';

import { AppError } from '../../common/http/http-error.filter';
import { PrismaService } from '../../common/prisma/prisma.service';
import { AuthService } from './auth.service';
import { MailerService } from './mailer.service';

interface MagicLinkTokenRow {
  id: string;
  email: string;
  tokenHash: string;
  expiresAt: Date;
  usedAt: Date | null;
  createdAt: Date;
}

interface RefreshTokenRow {
  id: string;
  userId: string;
  familyId: string;
  tokenHash: string;
  expiresAt: Date;
  revokedAt: Date | null;
}

function service(overrides?: {
  magicLinkToken?: MagicLinkTokenRow | null;
  refreshToken?: RefreshTokenRow | null;
  user?: { id: string; email: string; displayName: string | null };
  freeQuota?: number;
}) {
  const upsertedUser = overrides?.user ?? { id: 'user-1', email: 'a@b.com', displayName: null };

  const prisma = {
    magicLinkToken: {
      create: vi.fn(async () => ({})),
      findUnique: vi.fn(async () => overrides?.magicLinkToken ?? null),
      update: vi.fn(async () => ({})),
    },
    refreshToken: {
      create: vi.fn(async () => ({})),
      findUnique: vi.fn(async () => overrides?.refreshToken ?? null),
      update: vi.fn(async () => ({})),
      updateMany: vi.fn(async () => ({ count: 0 })),
    },
    user: {
      upsert: vi.fn(async () => upsertedUser),
    },
  } as unknown as PrismaService;

  const jwt = {
    signAsync: vi.fn(async () => 'signed-access-token'),
  } as unknown as JwtService;

  const mailer = {
    sendMagicLink: vi.fn(async () => undefined),
  } as unknown as MailerService;

  const config = {
    get: (key: string) => {
      if (key === 'MAGIC_LINK_TTL_MINUTES') return 10;
      if (key === 'JWT_REFRESH_TTL_DAYS') return 30;
      return undefined;
    },
  } as unknown as ConfigService;

  return { svc: new AuthService(prisma, jwt, mailer, config), prisma, jwt, mailer, config };
}

describe('AuthService (spec FR-S3-1, Rule 6, EC-S3-4, EC-S3-5)', () => {
  describe('requestMagicLink', () => {
    it('tạo token hash + gửi mail — không bao giờ throw dù email có tồn tại hay không', async () => {
      const { svc, prisma, mailer } = service();

      await svc.requestMagicLink('someone@example.com');

      expect(prisma.magicLinkToken.create).toHaveBeenCalledTimes(1);
      const createArgs = (prisma.magicLinkToken.create as ReturnType<typeof vi.fn>).mock
        .calls[0][0];
      expect(createArgs.data.email).toBe('someone@example.com');
      expect(createArgs.data.tokenHash).toMatch(/^[a-f0-9]{64}$/); // sha256 hex
      expect(mailer.sendMagicLink).toHaveBeenCalledWith(
        'someone@example.com',
        expect.any(String),
      );
    });
  });

  describe('verify', () => {
    it('reject token không tồn tại với AUTH_LINK_INVALID', async () => {
      const { svc } = service({ magicLinkToken: null });

      await expect(svc.verify('bogus-token')).rejects.toMatchObject({
        code: 'AUTH_LINK_INVALID',
      });
    });

    it('reject token đã hết hạn với AUTH_LINK_INVALID (không lộ lý do khác)', async () => {
      const expired: MagicLinkTokenRow = {
        id: 'ml-1',
        email: 'a@b.com',
        tokenHash: 'hash',
        expiresAt: new Date(Date.now() - 60_000),
        usedAt: null,
        createdAt: new Date(),
      };
      const { svc } = service({ magicLinkToken: expired });

      const err: AppError = await svc.verify('token').catch((e) => e as AppError);
      expect(err).toBeInstanceOf(AppError);
      expect(err.code).toBe('AUTH_LINK_INVALID');
      expect(err.getStatus()).toBe(401);
    });

    it('reject token đã dùng (usedAt set) với AUTH_LINK_INVALID — single-use', async () => {
      const used: MagicLinkTokenRow = {
        id: 'ml-2',
        email: 'a@b.com',
        tokenHash: 'hash',
        expiresAt: new Date(Date.now() + 60_000),
        usedAt: new Date(),
        createdAt: new Date(),
      };
      const { svc } = service({ magicLinkToken: used });

      await expect(svc.verify('token')).rejects.toMatchObject({
        code: 'AUTH_LINK_INVALID',
      });
    });

    it('happy path: đánh dấu used, upsert user, issue token pair', async () => {
      const valid: MagicLinkTokenRow = {
        id: 'ml-3',
        email: 'new@example.com',
        tokenHash: 'hash',
        expiresAt: new Date(Date.now() + 60_000),
        usedAt: null,
        createdAt: new Date(),
      };
      const user = { id: 'user-42', email: 'new@example.com', displayName: null };
      const { svc, prisma, jwt } = service({ magicLinkToken: valid, user });

      const result = await svc.verify('token');

      expect(prisma.magicLinkToken.update).toHaveBeenCalledWith({
        where: { id: 'ml-3' },
        data: { usedAt: expect.any(Date) },
      });
      expect(prisma.user.upsert).toHaveBeenCalledWith({
        where: { email: 'new@example.com' },
        create: { email: 'new@example.com' },
        update: {},
      });
      expect(jwt.signAsync).toHaveBeenCalledWith({ sub: 'user-42', plan: 'free' });
      expect(prisma.refreshToken.create).toHaveBeenCalledTimes(1);
      expect(result.accessToken).toBe('signed-access-token');
      expect(typeof result.refreshToken).toBe('string');
      expect(result.user).toEqual(user);
    });
  });

  describe('refresh', () => {
    it('reject refresh token không tồn tại với AUTH_TOKEN_INVALID', async () => {
      const { svc } = service({ refreshToken: null });

      await expect(svc.refresh('bogus')).rejects.toMatchObject({
        code: 'AUTH_TOKEN_INVALID',
      });
    });

    it('reject refresh token đã hết hạn với AUTH_TOKEN_INVALID', async () => {
      const expired: RefreshTokenRow = {
        id: 'rt-1',
        userId: 'user-1',
        familyId: 'fam-1',
        tokenHash: 'hash',
        expiresAt: new Date(Date.now() - 1000),
        revokedAt: null,
      };
      const { svc } = service({ refreshToken: expired });

      await expect(svc.refresh('token')).rejects.toMatchObject({
        code: 'AUTH_TOKEN_INVALID',
      });
    });

    it('reuse detection: refresh token đã revoked → revoke cả family + AUTH_TOKEN_REUSED (EC-S3-5)', async () => {
      const reused: RefreshTokenRow = {
        id: 'rt-2',
        userId: 'user-1',
        familyId: 'fam-2',
        tokenHash: 'hash',
        expiresAt: new Date(Date.now() + 60_000),
        revokedAt: new Date(), // đã bị revoke trước đó — dùng lại = reuse
      };
      const { svc, prisma } = service({ refreshToken: reused });

      await expect(svc.refresh('stolen-token')).rejects.toMatchObject({
        code: 'AUTH_TOKEN_REUSED',
      });

      expect(prisma.refreshToken.updateMany).toHaveBeenCalledWith({
        where: { familyId: 'fam-2', revokedAt: null },
        data: { revokedAt: expect.any(Date) },
      });
    });

    it('happy path: rotate — revoke token cũ, issue token mới cùng family', async () => {
      const current: RefreshTokenRow = {
        id: 'rt-3',
        userId: 'user-7',
        familyId: 'fam-7',
        tokenHash: 'hash',
        expiresAt: new Date(Date.now() + 60_000),
        revokedAt: null,
      };
      const { svc, prisma, jwt } = service({ refreshToken: current });

      const result = await svc.refresh('valid-token');

      expect(prisma.refreshToken.update).toHaveBeenCalledWith({
        where: { id: 'rt-3' },
        data: { revokedAt: expect.any(Date) },
      });
      expect(prisma.refreshToken.create).toHaveBeenCalledTimes(1);
      const createArgs = (prisma.refreshToken.create as ReturnType<typeof vi.fn>).mock
        .calls[0][0];
      expect(createArgs.data.familyId).toBe('fam-7');
      expect(createArgs.data.userId).toBe('user-7');
      expect(jwt.signAsync).toHaveBeenCalledWith({ sub: 'user-7', plan: 'free' });
      expect(result.accessToken).toBe('signed-access-token');
      expect(typeof result.refreshToken).toBe('string');
    });
  });
});
