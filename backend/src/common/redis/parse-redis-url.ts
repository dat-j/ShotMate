/**
 * Parse `redis://[:password@]host[:port][/db]` thành options object thay vì
 * dùng chuỗi `url` thẳng — các package dùng `ioredis` (bullmq bundle riêng
 * bản nested, rate-limit dùng bản top-level) gây lỗi type identity mismatch
 * nếu truyền instance `IORedis` xuyên package dù runtime tương thích. Object
 * options (plain interface) tránh vấn đề này hoàn toàn.
 *
 * Dùng chung bởi `modules/analysis/review.queue.ts`, `analysis.worker.ts` và
 * `common/rate-limit/redis-client.provider.ts` (FR-S4-4).
 */
export function parseRedisUrl(url: string): {
  host: string;
  port: number;
  password?: string;
  db?: number;
} {
  const parsed = new URL(url);
  const db =
    parsed.pathname && parsed.pathname !== '/' ? Number(parsed.pathname.slice(1)) : undefined;
  return {
    host: parsed.hostname || 'localhost',
    port: parsed.port ? Number(parsed.port) : 6379,
    ...(parsed.password ? { password: parsed.password } : {}),
    ...(db !== undefined && !Number.isNaN(db) ? { db } : {}),
  };
}
