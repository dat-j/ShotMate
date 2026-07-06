/**
 * Shape tối thiểu của RevenueCat webhook event mà ShotMate quan tâm
 * (spec FR-S3-5, Rule 3). Payload đầy đủ RevenueCat có nhiều field hơn —
 * chỉ khai những field backend dùng, phần còn lại bỏ qua an toàn.
 */
export interface RevenueCatWebhookBody {
  event?: RevenueCatEvent;
}

export interface RevenueCatEvent {
  type?: string; // INITIAL_PURCHASE | RENEWAL | CANCELLATION | EXPIRATION | ...
  app_user_id?: string;
  expiration_at_ms?: number | null;
  store?: string; // apple | google | ...
}

export const REVENUECAT_ACTIVE_EVENT_TYPES = new Set([
  'INITIAL_PURCHASE',
  'RENEWAL',
]);

export const REVENUECAT_INACTIVE_EVENT_TYPES = new Set([
  'CANCELLATION',
  'EXPIRATION',
]);
