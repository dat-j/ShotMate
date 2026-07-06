import { Injectable } from '@nestjs/common';

import { PrismaService } from '../../common/prisma/prisma.service';

export interface CreditStatus {
  usedToday: number;
  quota: number; // -1 = unlimited (premium)
  remainingToday: number; // -1 = unlimited
}

/** Executor cho raw SQL — PrismaService hoặc TransactionClient (dùng trong $transaction). */
type RawExecutor = Pick<PrismaService, '$executeRaw'>;

/**
 * Credits server-side (spec FR-S3-4, Rule 2). Ngày theo UTC của server.
 *
 * Trừ/hoàn ATOMIC bằng raw SQL với điều kiện trong chính câu UPDATE để
 * chống race (EC-S3-1): 2 request song song khi còn 1 lượt → đúng 1 pass.
 */
@Injectable()
export class CreditsService {
  constructor(private readonly prisma: PrismaService) {}

  /** Quota theo plan hiện hành: premium unlimited (-1), free = FREE_DAILY_QUOTA. */
  private quotaForPlan(plan: string, freeQuota: number): number {
    return plan === 'premium' ? -1 : freeQuota;
  }

  async status(userId: string, plan: string, freeQuota: number): Promise<CreditStatus> {
    const quota = this.quotaForPlan(plan, freeQuota);
    const row = await this.prisma.credit.findUnique({
      where: { userId_day: { userId, day: this.today() } },
    });
    const used = row?.used ?? 0;
    return {
      usedToday: used,
      quota,
      remainingToday: quota === -1 ? -1 : Math.max(0, quota - used),
    };
  }

  /**
   * Trừ 1 credit atomic. Trả về remaining (>=0) nếu thành công, hoặc null nếu
   * hết quota. Dùng ON CONFLICT với WHERE guard để đúng 1 request thắng race.
   */
  async tryConsume(
    userId: string,
    plan: string,
    freeQuota: number,
  ): Promise<{ remaining: number } | null> {
    const quota = this.quotaForPlan(plan, freeQuota);

    // INSERT ... ON CONFLICT DO UPDATE ... WHERE guard: nếu đã đạt quota,
    // UPDATE không match row nào → RETURNING rỗng → null (402).
    //
    // quota được cập nhật theo plan HIỆN HÀNH mỗi lần (EXCLUDED.quota) trước
    // khi đánh giá guard — nếu không, user free hết 10 lượt rồi mua premium
    // giữa ngày sẽ vẫn bị chặn vì row cũ còn quota=10 (EC-S3-3). Guard so
    // `used < EXCLUDED.quota` để quota mới (kể cả -1 unlimited) có hiệu lực ngay.
    const rows = await this.prisma.$queryRaw<Array<{ used: number; quota: number }>>`
      INSERT INTO credits (id, user_id, day, used, quota)
      VALUES (gen_random_uuid(), ${userId}::uuid, CURRENT_DATE, 1, ${quota})
      ON CONFLICT (user_id, day) DO UPDATE
        SET used = credits.used + 1, quota = EXCLUDED.quota
        WHERE EXCLUDED.quota = -1 OR credits.used < EXCLUDED.quota
      RETURNING used, quota
    `;

    const row = rows[0];
    if (!row) return null; // hết quota
    return {
      remaining: row.quota === -1 ? -1 : Math.max(0, row.quota - row.used),
    };
  }

  /**
   * Hoàn 1 credit khi review thất bại chung cuộc (spec Rule 2, Rule 7).
   * Không giảm dưới 0. No-op nếu row không tồn tại (đã sang ngày khác).
   *
   * Nhận `executor` tuỳ chọn để chạy TRONG cùng transaction với việc cập nhật
   * status=failed (Rule 2: "hoàn 1 credit trong cùng transaction") — tránh
   * trạng thái lệch nếu process crash giữa hai bước (review.processor).
   */
  async refund(
    userId: string,
    day?: Date,
    executor: RawExecutor = this.prisma,
  ): Promise<void> {
    await executor.$executeRaw`
      UPDATE credits
        SET used = GREATEST(0, used - 1)
      WHERE user_id = ${userId}::uuid
        AND day = ${day ?? this.todayDate()}::date
    `;
  }

  private today(): Date {
    return this.todayDate();
  }

  private todayDate(): Date {
    const now = new Date();
    return new Date(
      Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()),
    );
  }
}
