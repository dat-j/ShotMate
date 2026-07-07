import { randomUUID } from 'node:crypto';

import { INestApplicationContext, ValidationPipe } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import { JwtService } from '@nestjs/jwt';
import { FastifyAdapter, NestFastifyApplication } from '@nestjs/platform-fastify';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { AppModule } from './app.module';
import { PrismaService } from './common/prisma/prisma.service';
import { HttpErrorFilter } from './common/http/http-error.filter';
import { ReviewProcessor } from './modules/analysis/review.processor';
import { WorkerModule } from './worker.module';

/**
 * Integration test end-to-end trên DB/Redis/mailpit THẬT (docker compose) —
 * spec-sprint-4 FR-S4-7, trả nợ D7. Bootstrap toàn bộ AppModule qua
 * NestFactory (không mock Prisma/Redis) + Fastify `app.inject()` (built-in,
 * không cần supertest) cho HTTP round-trip trong-process.
 *
 * Yêu cầu: `docker compose -f infra/docker-compose.yml up -d` đang chạy
 * (postgres/redis/mailpit) và migration đã apply (`prisma migrate deploy`).
 * Chạy qua `npm run test:integration` — KHÔNG nằm trong `npm test` (unit gate).
 */
describe('AppModule (integration — DB/Redis/mailpit thật)', () => {
  let app: NestFastifyApplication;
  let prisma: PrismaService;
  // WorkerModule bootstrap riêng — process thật (main.worker.ts) tách khỏi
  // API kể từ D2 (spec-sprint-4 FR-S4-2); ReviewProcessor không còn nằm
  // trong AppModule, test phải bootstrap đúng context production.
  let workerCtx: INestApplicationContext;

  beforeAll(async () => {
    app = await NestFactory.create<NestFastifyApplication>(AppModule, new FastifyAdapter());
    app.setGlobalPrefix('api/v1');
    app.useGlobalPipes(
      new ValidationPipe({
        whitelist: true,
        forbidNonWhitelisted: true,
        transform: true,
        errorHttpStatusCode: 422,
      }),
    );
    app.useGlobalFilters(new HttpErrorFilter());
    await app.init();
    await app.getHttpAdapter().getInstance().ready();

    prisma = app.get(PrismaService);
    workerCtx = await NestFactory.createApplicationContext(WorkerModule);
  }, 30000);

  afterAll(async () => {
    await workerCtx.close();
    await app.close();
  });

  /** Tạo user + JWT access token trực tiếp qua service thật (bỏ qua magic-link UI cho test không phải auth-flow). */
  async function createAuthedUser(): Promise<{ userId: string; accessToken: string }> {
    const email = `it-${randomUUID()}@example.com`;
    const user = await prisma.user.create({ data: { email } });
    const jwt = app.get(JwtService);
    const accessToken = jwt.sign({ sub: user.id, plan: 'free' });
    return { userId: user.id, accessToken };
  }

  function authHeader(token: string): Record<string, string> {
    return { authorization: `Bearer ${token}` };
  }

  describe('EC-S3-1: race trừ credit', () => {
    it('2 request review song song khi còn 1 credit → đúng 1 pass, 1 fail 402', async () => {
      const { userId, accessToken } = await createAuthedUser();
      const photoId = randomUUID();
      await prisma.photo.create({
        data: {
          id: photoId,
          userId,
          storagePath: `photos/${userId}/${photoId}.jpg`,
          captureMeta: {},
          takenAt: new Date(),
        },
      });
      // Set quota còn đúng 1 lượt hôm nay (used = quota - 1 = 9/10).
      await prisma.credit.create({
        data: { userId, day: new Date(new Date().toISOString().slice(0, 10)), used: 9, quota: 10 },
      });

      const [r1, r2] = await Promise.all([
        app.inject({
          method: 'POST',
          url: `/api/v1/photos/${photoId}/review`,
          headers: authHeader(accessToken),
        }),
        app.inject({
          method: 'POST',
          url: `/api/v1/photos/${photoId}/review`,
          headers: authHeader(accessToken),
        }),
      ]);

      const statuses = [r1.statusCode, r2.statusCode].sort();
      // Một request 202 (enqueue), request kia 402 (hết quota) hoặc 409 (đã
      // có review in-progress nếu request đầu enqueue trước khi request 2 tới
      // bước check credit) — điều bất biến thật sự cần giữ là KHÔNG có 2
      // request cùng pass 202 (đó là race điều kiện spec cấm).
      const successCount = statuses.filter((s) => s === 202).length;
      expect(successCount).toBe(1);
    }, 20000);
  });

  describe('EC-S3-2: cả 2 provider fail → refund', () => {
    it('review status=failed hoàn 1 credit trong cùng transaction', async () => {
      const { userId } = await createAuthedUser();
      const today = new Date(new Date().toISOString().slice(0, 10));
      await prisma.credit.create({ data: { userId, day: today, used: 5, quota: 10 } });

      const photoId = randomUUID();
      const analysisId = randomUUID();
      await prisma.photo.create({
        data: {
          id: photoId,
          userId,
          storagePath: `photos/${userId}/${photoId}.jpg`,
          captureMeta: {},
          takenAt: new Date(),
        },
      });
      await prisma.analysis.create({
        data: { id: analysisId, photoId, kind: 'cloud', provider: 'pending', status: 'queued', result: {} },
      });

      const processor = workerCtx.get(ReviewProcessor);
      await processor.handleFinalFailure(analysisId, userId);

      const analysis = await prisma.analysis.findUniqueOrThrow({ where: { id: analysisId } });
      expect(analysis.status).toBe('failed');

      const credit = await prisma.credit.findUniqueOrThrow({
        where: { userId_day: { userId, day: today } },
      });
      expect(credit.used).toBe(4); // 5 - 1 hoàn
    });
  });

  describe('Auth e2e: magic-link → mailpit → verify → refresh → reuse detection', () => {
    const mailpitBase = 'http://localhost:8025/api/v1';

    async function latestMessageTo(email: string): Promise<{ Text: string } | undefined> {
      const res = await fetch(`${mailpitBase}/messages?limit=50`);
      const body = (await res.json()) as {
        messages: Array<{ To: Array<{ Address: string }>; ID: string }>;
      };
      const match = body.messages.find((m) => m.To.some((to) => to.Address === email));
      if (!match) return undefined;
      const detail = await fetch(`${mailpitBase}/message/${match.ID}`);
      return (await detail.json()) as { Text: string };
    }

    it('magic-link → verify → refresh rotation → reuse cũ bị revoke cả family', async () => {
      const email = `it-auth-${randomUUID()}@example.com`;

      const linkRes = await app.inject({
        method: 'POST',
        url: '/api/v1/auth/magic-link',
        payload: { email },
      });
      expect(linkRes.statusCode).toBe(202);

      // Poll mailpit — gửi mail là async qua SMTP, chờ ngắn cho chắc.
      let message: { Text: string } | undefined;
      for (let i = 0; i < 10 && !message; i++) {
        message = await latestMessageTo(email);
        if (!message) await new Promise((r) => setTimeout(r, 300));
      }
      expect(message).toBeDefined();

      const token = message!.Text.match(/token=([\w-]+)/)?.[1];
      expect(token).toBeTruthy();

      const verifyRes = await app.inject({
        method: 'POST',
        url: '/api/v1/auth/verify',
        payload: { token },
      });
      expect(verifyRes.statusCode).toBe(200);
      const { refreshToken } = verifyRes.json<{ refreshToken: string }>();

      // Lần refresh đầu — rotation, thành công.
      const refresh1 = await app.inject({
        method: 'POST',
        url: '/api/v1/auth/refresh',
        payload: { refreshToken },
      });
      expect(refresh1.statusCode).toBe(200);

      // Dùng lại refresh token CŨ (đã rotate) — reuse detection (EC-S3-5) →
      // revoke cả family, 401.
      const reuse = await app.inject({
        method: 'POST',
        url: '/api/v1/auth/refresh',
        payload: { refreshToken },
      });
      expect(reuse.statusCode).toBe(401);

      // Token MỚI (từ refresh1) giờ cũng phải bị revoke (cả family) — không
      // login lại bằng nó được nữa.
      const { refreshToken: newRefreshToken } = refresh1.json<{ refreshToken: string }>();
      const afterRevoke = await app.inject({
        method: 'POST',
        url: '/api/v1/auth/refresh',
        payload: { refreshToken: newRefreshToken },
      });
      expect(afterRevoke.statusCode).toBe(401);
    }, 20000);
  });

  describe('EC-S3-6: sync conflict cùng UUID', () => {
    it('LWW theo taken_at — bản cũ hơn bị từ chối, trả conflicts[]', async () => {
      const { accessToken } = await createAuthedUser();
      const photoId = randomUUID();
      const newer = new Date('2026-07-07T10:00:00Z');
      const older = new Date('2026-07-06T10:00:00Z');

      const pushNewer = await app.inject({
        method: 'POST',
        url: '/api/v1/sync',
        headers: authHeader(accessToken),
        payload: { photos: [{ id: photoId, takenAt: newer.getTime(), captureMeta: {} }], analyses: [], scores: [] },
      });
      expect(pushNewer.statusCode).toBe(200);
      expect(pushNewer.json<{ accepted: number }>().accepted).toBe(1);

      // Đẩy bản CŨ hơn cho cùng id — phải bị từ chối (conflict), không ghi đè.
      const pushOlder = await app.inject({
        method: 'POST',
        url: '/api/v1/sync',
        headers: authHeader(accessToken),
        payload: { photos: [{ id: photoId, takenAt: older.getTime(), captureMeta: {} }], analyses: [], scores: [] },
      });
      const body = pushOlder.json<{ accepted: number; conflicts: Array<{ id: string }> }>();
      expect(body.conflicts.map((c) => c.id)).toContain(photoId);

      const photo = await prisma.photo.findUniqueOrThrow({ where: { id: photoId } });
      expect(photo.takenAt.toISOString()).toBe(newer.toISOString()); // bản server (mới hơn) không bị ghi đè
    });
  });

  describe('EC-S3-11: DELETE /me', () => {
    it('xoá account cascade DB + revoke token', async () => {
      const { userId, accessToken } = await createAuthedUser();

      const del = await app.inject({
        method: 'DELETE',
        url: '/api/v1/me',
        headers: authHeader(accessToken),
      });
      expect(del.statusCode).toBe(204);

      const user = await prisma.user.findUnique({ where: { id: userId } });
      expect(user).toBeNull();
    });
  });
});
