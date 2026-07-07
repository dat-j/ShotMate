import { SetMetadata } from '@nestjs/common';

export const RATE_LIMIT_KEY = 'rateLimitRules';

/** 1 rule rate-limit áp cho 1 route (FR-S4-4 bảng scope). */
export interface RateLimitRule {
  /** Tên ngắn dùng làm phần đầu Redis key + log (vd: "magic-link-email"). */
  name: string;
  limit: number;
  windowSeconds: number;
  /** 'ip' | 'email' | 'user' — nguồn định danh cho counter. */
  keyBy: 'ip' | 'email' | 'user';
}

/**
 * @RateLimit(...) — gắn 1 hoặc nhiều rule vào route, enforce bởi
 * `RateLimitGuard`. Nhiều rule trên cùng route đều phải pass (spec:
 * magic-link cần CẢ email VÀ IP limit).
 */
export const RateLimit = (...rules: RateLimitRule[]): MethodDecorator =>
  SetMetadata(RATE_LIMIT_KEY, rules);
