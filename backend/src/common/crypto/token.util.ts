import { createHash, randomBytes, timingSafeEqual } from 'node:crypto';

/**
 * Token helpers cho magic-link + refresh token (spec Rule 6).
 * Token raw chỉ tồn tại ở mail/client; server lưu SHA-256 hash.
 */

/** Sinh token ngẫu nhiên URL-safe (mặc định 32 byte = 256-bit entropy). */
export function generateToken(bytes = 32): string {
  return randomBytes(bytes).toString('base64url');
}

/** SHA-256 hex — dùng làm khoá tra cứu (unique index) an toàn. */
export function hashToken(token: string): string {
  return createHash('sha256').update(token).digest('hex');
}

/** So sánh constant-time cho secret (webhook, header) — chống timing attack. */
export function safeEqual(a: string, b: string): boolean {
  const ba = Buffer.from(a);
  const bb = Buffer.from(b);
  if (ba.length !== bb.length) return false;
  return timingSafeEqual(ba, bb);
}
