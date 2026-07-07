import { z } from 'zod';

/**
 * Env schema — validate lúc bootstrap (ConfigModule.forRoot validate).
 * Thiếu biến bắt buộc → app fail fast thay vì lỗi runtime khó truy.
 * Secrets: local .env (gitignored), prod GCP Secret Manager.
 */
export const envSchema = z.object({
  PORT: z.coerce.number().default(8080),
  DATABASE_URL: z.string().min(1),
  REDIS_URL: z.string().min(1),

  JWT_SECRET: z.string().min(16),
  JWT_ACCESS_TTL: z.string().default('15m'),
  JWT_REFRESH_TTL_DAYS: z.coerce.number().default(30),

  // Cloud AI review (ADR-0004)
  AI_REVIEW_PRIMARY: z.enum(['claude', 'gemini']).default('claude'),
  ANTHROPIC_API_KEY: z.string().optional(),
  CLAUDE_REVIEW_MODEL: z.string().default('claude-haiku-4-5'),
  GEMINI_API_KEY: z.string().optional(),
  GEMINI_REVIEW_MODEL: z.string().default('gemini-2.5-flash'),
  // Vertex AI (fallback billing GCP project — tránh prepayment credit AI
  // Studio dùng chung bởi GEMINI_API_KEY). ADC (service account Cloud Run),
  // không cần API key.
  VERTEX_PROJECT_ID: z.string().optional(),
  VERTEX_LOCATION: z.string().default('us-central1'),
  VERTEX_REVIEW_MODEL: z.string().default('gemini-2.5-flash'),

  // Storage (local: minio; prod: GCS)
  GCS_BUCKET: z.string().default('shotmate-photos-dev'),
  STORAGE_ENDPOINT: z.string().optional(), // minio local; bỏ trống = GCS thật
  STORAGE_ACCESS_KEY: z.string().optional(),
  STORAGE_SECRET_KEY: z.string().optional(),
  STORAGE_REGION: z.string().default('auto'),
  SIGNED_URL_TTL_SECONDS: z.coerce.number().default(900),
  UPLOAD_MAX_BYTES: z.coerce.number().default(10 * 1024 * 1024),

  // Email magic link (local: mailpit)
  SMTP_HOST: z.string().default('localhost'),
  SMTP_PORT: z.coerce.number().default(1025),
  SMTP_FROM: z.string().default('noreply@shotmate.app'),
  MAGIC_LINK_BASE_URL: z.string().default('https://shotmate.app/auth/verify'),
  MAGIC_LINK_TTL_MINUTES: z.coerce.number().default(10),

  // Credits
  FREE_DAILY_QUOTA: z.coerce.number().default(10),

  // Subscription (RevenueCat webhook)
  REVENUECAT_WEBHOOK_SECRET: z.string().optional(),
  REVENUECAT_API_KEY: z.string().optional(),
});

export type Env = z.infer<typeof envSchema>;

export function validateEnv(config: Record<string, unknown>): Env {
  const parsed = envSchema.safeParse(config);
  if (!parsed.success) {
    const issues = parsed.error.issues
      .map((i) => `${i.path.join('.')}: ${i.message}`)
      .join('; ');
    throw new Error(`Invalid environment configuration: ${issues}`);
  }
  return parsed.data;
}
