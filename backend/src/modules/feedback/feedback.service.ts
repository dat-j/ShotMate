import { Injectable } from '@nestjs/common';

import { PrismaService } from '../../common/prisma/prisma.service';
import { FeedbackDto } from './dto/feedback.dto';

/** FeedbackService — persist feedback cho tuning (spec FR-S3-10). */
@Injectable()
export class FeedbackService {
  constructor(private readonly prisma: PrismaService) {}

  async create(userId: string, dto: FeedbackDto): Promise<{ id: string }> {
    const feedback = await this.prisma.feedback.create({
      data: {
        userId,
        targetKind: dto.targetKind,
        targetRef: dto.targetRef,
        rating: dto.rating,
        comment: dto.comment ?? null,
      },
    });

    return { id: feedback.id };
  }
}
