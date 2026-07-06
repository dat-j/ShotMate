import { Injectable, Logger } from '@nestjs/common';
import { Prisma } from '@prisma/client';

import { PrismaService } from '../../common/prisma/prisma.service';
import { AiReviewService } from '../ai-review/ai-review.service';
import { CreditsService } from '../credits/credits.service';
import { StorageService } from '../photos/storage.service';

/**
 * ReviewProcessor — logic BullMQ job handler, extracted from the actual
 * `Worker` wiring (analysis.worker.ts) so it's unit-testable without a live
 * queue (spec constraint). Single-attempt per call; BullMQ handles retry via
 * `attempts`/`backoff` configured on the job (Rule 7).
 */
@Injectable()
export class ReviewProcessor {
  private readonly logger = new Logger(ReviewProcessor.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly storage: StorageService,
    private readonly aiReview: AiReviewService,
    private readonly credits: CreditsService,
  ) {}

  async process(analysisId: string): Promise<void> {
    const analysis = await this.prisma.analysis.findUniqueOrThrow({
      where: { id: analysisId },
      include: { photo: true },
    });

    const base64 = await this.storage.getObjectBase64(analysis.photo.storagePath as string);

    const reviewed = await this.aiReview.review(base64, {
      sceneType: analysis.photo.sceneType ?? undefined,
    });

    await this.prisma.$transaction([
      this.prisma.analysis.update({
        where: { id: analysisId },
        data: {
          status: 'done',
          provider: reviewed.provider,
          result: {
            scores: reviewed.scores,
            explanation: reviewed.explanation,
            suggestions: reviewed.suggestions,
          } as Prisma.InputJsonValue,
        },
      }),
      this.prisma.score.upsert({
        where: { analysisId },
        create: {
          analysisId,
          composition: reviewed.scores.composition,
          lighting: reviewed.scores.lighting,
          focus: reviewed.scores.focus,
          background: reviewed.scores.background,
        },
        update: {
          composition: reviewed.scores.composition,
          lighting: reviewed.scores.lighting,
          focus: reviewed.scores.focus,
          background: reviewed.scores.background,
        },
      }),
    ]);
  }

  /**
   * Review thất bại chung cuộc (hết retry) — spec Rule 2, Rule 7, EC-S3-2.
   * status=failed + hoàn 1 credit TRONG CÙNG transaction (Rule 2) — nếu
   * process crash giữa hai bước sẽ không để lại trạng thái lệch (failed mà
   * chưa hoàn credit, hoặc ngược lại).
   */
  async handleFinalFailure(analysisId: string, userId: string): Promise<void> {
    this.logger.warn(`Review ${analysisId} failed chung cuộc — refund credit cho ${userId}`);
    await this.prisma.$transaction(async (tx) => {
      await tx.analysis.update({
        where: { id: analysisId },
        data: { status: 'failed' },
      });
      await this.credits.refund(userId, undefined, tx);
    });
  }
}
