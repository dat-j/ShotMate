import { Injectable, Logger, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Job, Worker } from 'bullmq';

import { PrismaService } from '../../common/prisma/prisma.service';
import { parseRedisUrl, ReviewJobPayload } from './review.queue';
import { ReviewProcessor } from './review.processor';

const MAX_ATTEMPTS = 3;

/**
 * AnalysisWorker — wires the real BullMQ `Worker('ai-review', ...)` (spec
 * FR-S3-3, Event Changes): concurrency 5. `attempts: 3` + exponential
 * backoff base 2s are job-level options (BullMQ `WorkerOptions` has no such
 * fields) — configured where the job is enqueued (AnalysisService.requestReview).
 * MAX_ATTEMPTS here is only used to detect the final failed attempt in the
 * `failed` event handler below.
 *
 * Connects to Redis only in `onModuleInit` (never in the constructor) so
 * importing AnalysisModule in tests never requires a live Redis instance.
 * Skipped entirely under NODE_ENV=test (spec constraint).
 */
@Injectable()
export class AnalysisWorker implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(AnalysisWorker.name);
  private worker: Worker<ReviewJobPayload> | undefined;

  constructor(
    private readonly config: ConfigService,
    private readonly processor: ReviewProcessor,
    private readonly prisma: PrismaService,
  ) {}

  onModuleInit(): void {
    if (process.env.NODE_ENV === 'test') {
      return;
    }

    const redisUrl = this.config.get<string>('REDIS_URL') ?? 'redis://localhost:6379';

    this.worker = new Worker<ReviewJobPayload>(
      'ai-review',
      async (job: Job<ReviewJobPayload>) => {
        await this.processor.process(job.data.analysisId);
      },
      {
        connection: { ...parseRedisUrl(redisUrl), maxRetriesPerRequest: null },
        concurrency: 5,
      },
    );

    this.worker.on('failed', (job, error) => {
      void this.onJobFailed(job, error);
    });
  }

  private async onJobFailed(
    job: Job<ReviewJobPayload> | undefined,
    error: Error,
  ): Promise<void> {
    if (!job) return;
    this.logger.error(
      `Job ${job.id} (analysis ${job.data.analysisId}) failed attempt ${job.attemptsMade}: ${error.message}`,
    );
    if (job.attemptsMade < MAX_ATTEMPTS) {
      return; // còn retry, BullMQ tự requeue theo backoff.
    }

    const analysis = await this.prisma.analysis.findUnique({
      where: { id: job.data.analysisId },
      include: { photo: true },
    });
    if (!analysis) return;

    await this.processor.handleFinalFailure(analysis.id, analysis.photo.userId);
  }

  async onModuleDestroy(): Promise<void> {
    await this.worker?.close();
  }
}
