import { describe, expect, it, vi } from 'vitest';

import { PrismaService } from '../../common/prisma/prisma.service';
import { FeedbackDto } from './dto/feedback.dto';
import { FeedbackService } from './feedback.service';

function service(createResult?: { id: string }) {
  const prisma = {
    feedback: {
      create: vi.fn(async () => createResult ?? { id: 'fb-1' }),
    },
  } as unknown as PrismaService;

  return { svc: new FeedbackService(prisma), prisma };
}

describe('FeedbackService (spec FR-S3-10)', () => {
  it('persists feedback với userId từ arg (không phải từ dto)', async () => {
    const { svc, prisma } = service({ id: 'fb-42' });
    const dto: FeedbackDto = {
      targetKind: 'review',
      targetRef: 'analysis-1',
      rating: 1,
      comment: 'Rất chính xác',
    };

    const result = await svc.create('user-1', dto);

    expect(prisma.feedback.create).toHaveBeenCalledWith({
      data: {
        userId: 'user-1',
        targetKind: 'review',
        targetRef: 'analysis-1',
        rating: 1,
        comment: 'Rất chính xác',
      },
    });
    expect(result).toEqual({ id: 'fb-42' });
  });

  it('comment optional → lưu null khi không có', async () => {
    const { svc, prisma } = service();
    const dto: FeedbackDto = {
      targetKind: 'hint',
      targetRef: 'hint-zoom',
      rating: -1,
    };

    await svc.create('user-2', dto);

    expect(prisma.feedback.create).toHaveBeenCalledWith({
      data: {
        userId: 'user-2',
        targetKind: 'hint',
        targetRef: 'hint-zoom',
        rating: -1,
        comment: null,
      },
    });
  });
});
