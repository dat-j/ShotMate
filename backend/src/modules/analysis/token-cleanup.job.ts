import { Injectable, Logger, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Queue, Worker } from 'bullmq';

import { PrismaService } from '../../common/prisma/prisma.service';
import { parseRedisUrl } from './review.queue';

const TOKEN_CLEANUP_QUEUE = 'token-cleanup';
const RETENTION_DAYS = 7;
const REPEAT_EVERY_MS = 24 * 60 * 60 * 1000; // 1 lần/ngày

/**
 * TokenCleanupJob — BullMQ repeatable job xoá MagicLinkToken/RefreshToken hết
 * hạn quá 7 ngày (spec-sprint-3 Database Changes). Chỉ chạy ở worker service
 * (FR-S4-2) — API không còn khởi động job này.
 *
 * Connects to Redis only in `onModuleInit` (never in the constructor), giống
 * pattern AnalysisWorker — importing module này trong test không cần Redis
 * sống. Skipped hoàn toàn dưới NODE_ENV=test.
 */
@Injectable()
export class TokenCleanupJob implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(TokenCleanupJob.name);
  private queue: Queue | undefined;
  private worker: Worker | undefined;

  constructor(
    private readonly config: ConfigService,
    private readonly prisma: PrismaService,
  ) {}

  async onModuleInit(): Promise<void> {
    if (process.env.NODE_ENV === 'test') {
      return;
    }

    const redisUrl = this.config.get<string>('REDIS_URL') ?? 'redis://localhost:6379';
    const connection = { ...parseRedisUrl(redisUrl), maxRetriesPerRequest: null };

    this.queue = new Queue(TOKEN_CLEANUP_QUEUE, { connection });
    this.worker = new Worker(
      TOKEN_CLEANUP_QUEUE,
      async () => {
        await this.cleanup();
      },
      { connection },
    );

    this.worker.on('failed', (job, error) => {
      this.logger.error(`Token cleanup job ${job?.id} failed: ${error.message}`);
    });

    await this.queue.add(
      'cleanup',
      {},
      {
        repeat: { every: REPEAT_EVERY_MS },
        jobId: 'token-cleanup-daily',
      },
    );
  }

  async cleanup(): Promise<void> {
    const cutoff = new Date(Date.now() - RETENTION_DAYS * 24 * 60 * 60 * 1000);

    const [magicLinks, refreshTokens] = await this.prisma.$transaction([
      this.prisma.magicLinkToken.deleteMany({ where: { expiresAt: { lt: cutoff } } }),
      this.prisma.refreshToken.deleteMany({ where: { expiresAt: { lt: cutoff } } }),
    ]);

    this.logger.log(
      `Token cleanup: xoá ${magicLinks.count} magic link + ${refreshTokens.count} refresh token hết hạn > ${RETENTION_DAYS} ngày`,
    );
  }

  async onModuleDestroy(): Promise<void> {
    await this.worker?.close();
    await this.queue?.close();
  }
}
