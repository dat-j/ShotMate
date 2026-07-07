import { z } from 'zod';

/**
 * Shape tối thiểu của RevenueCat webhook event mà ShotMate quan tâm
 * (spec FR-S4-5/D4, Security S3: validate webhook payload — CWE-20).
 * Payload đầy đủ RevenueCat có nhiều field hơn — chỉ khai + validate những
 * field backend dùng; `.passthrough()` để field lạ RevenueCat gửi thêm
 * không bị zod strict-reject (bỏ qua an toàn, không lỗi).
 *
 * Field bắt buộc: `type`, `app_user_id` — thiếu → controller ném
 * AppError(422, 'VALIDATION_FAILED', ...). Field khác optional.
 */
export const revenueCatEventSchema = z
  .object({
    type: z.string().min(1), // INITIAL_PURCHASE | RENEWAL | CANCELLATION | EXPIRATION | ...
    app_user_id: z.string().min(1),
    expiration_at_ms: z.number().nullable().optional(),
    store: z.string().optional(), // apple | google | ...
  })
  .passthrough();

export const revenueCatWebhookBodySchema = z
  .object({
    event: revenueCatEventSchema,
  })
  .passthrough();

export type RevenueCatEvent = z.infer<typeof revenueCatEventSchema>;
export type RevenueCatWebhookBody = z.infer<typeof revenueCatWebhookBodySchema>;

/**
 * Shape thô (chưa validate) nhận từ Nest @Body() — field đều optional vì
 * payload có thể thiếu/sai; controller tự parse bằng zod schema ở trên
 * để trả 422 thay vì để lỗi runtime khi truy cập field thiếu.
 */
export interface RawRevenueCatWebhookBody {
  event?: Partial<RevenueCatEvent> & Record<string, unknown>;
}

export const REVENUECAT_ACTIVE_EVENT_TYPES = new Set([
  'INITIAL_PURCHASE',
  'RENEWAL',
]);

export const REVENUECAT_INACTIVE_EVENT_TYPES = new Set([
  'CANCELLATION',
  'EXPIRATION',
]);
