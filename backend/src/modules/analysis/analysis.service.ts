import { randomUUID } from 'node:crypto';

import { Inject, Injectable } from '@nestjs/common';
import type { Queue } from 'bullmq';

import { AppError } from '../../common/http/http-error.filter';
import { PrismaService } from '../../common/prisma/prisma.service';
import { CreditsService } from '../credits/credits.service';
import { PhotosService } from '../photos/photos.service';
import { ReviewJobPayload, REVIEW_QUEUE } from './review.queue';

const IN_PROGRESS_STATUSES = ['queued', 'processing'];

export interface RequestReviewResult {
  reviewId: string;
  status: 'QUEUED';
  creditsRemaining: number;
}

export interface ReviewResultView {
  reviewId: string;
  status: string;
  provider: string;
  scores?: { composition: number; lighting: number; focus: number; background: number };
  explanation?: string;
  suggestions?: string[];
  createdAt: Date;
}

/**
 * AnalysisService — enqueue cloud review + poll kết quả (spec FR-S3-3).
 * Credit trừ ATOMIC qua CreditsService.tryConsume — never read-then-write
 * (Rule 2, EC-S3-1).
 */
@Injectable()
export class AnalysisService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly photos: PhotosService,
    private readonly credits: CreditsService,
    @Inject(REVIEW_QUEUE) private readonly queue: Queue<ReviewJobPayload>,
  ) {}

  async requestReview(
    userId: string,
    plan: string,
    freeQuota: number,
    photoId: string,
  ): Promise<RequestReviewResult> {
    const photo = await this.photos.findOwned(userId, photoId);

    if (photo.storagePath == null) {
      throw new AppError(422, 'PHOTO_NOT_UPLOADED', 'Photo chưa được upload lên storage');
    }

    const inProgress = await this.prisma.analysis.findFirst({
      where: { photoId, kind: 'cloud', status: { in: IN_PROGRESS_STATUSES } },
    });
    if (inProgress) {
      throw new AppError(409, 'REVIEW_IN_PROGRESS', 'Review đang xử lý cho ảnh này');
    }

    const consumed = await this.credits.tryConsume(userId, plan, freeQuota);
    if (!consumed) {
      throw new AppError(402, 'CREDITS_EXHAUSTED', 'Hết lượt review AI hôm nay');
    }

    const analysis = await this.prisma.analysis.create({
      data: {
        id: randomUUID(),
        photoId,
        kind: 'cloud',
        provider: 'pending',
        status: 'queued',
        result: {},
      },
    });

    await this.queue.add(
      'review',
      { analysisId: analysis.id },
      { attempts: 3, backoff: { type: 'exponential', delay: 2000 } },
    );

    return {
      reviewId: analysis.id,
      status: 'QUEUED',
      creditsRemaining: consumed.remaining,
    };
  }

  async getReview(userId: string, photoId: string): Promise<ReviewResultView> {
    // Ownership check trước — 404 PHOTO_NOT_FOUND nếu photo không phải của user này.
    await this.photos.findOwned(userId, photoId);

    const analysis = await this.prisma.analysis.findFirst({
      where: { photoId, kind: 'cloud' },
      orderBy: { createdAt: 'desc' },
    });
    if (!analysis) {
      throw new AppError(404, 'REVIEW_NOT_FOUND', 'Chưa có review nào cho ảnh này');
    }

    const result = analysis.result as {
      scores?: ReviewResultView['scores'];
      explanation?: string;
      suggestions?: string[];
    };

    return {
      reviewId: analysis.id,
      status: analysis.status,
      provider: analysis.provider,
      createdAt: analysis.createdAt,
      ...(analysis.status === 'done'
        ? {
            scores: result.scores,
            explanation: result.explanation,
            suggestions: result.suggestions,
          }
        : {}),
    };
  }
}
