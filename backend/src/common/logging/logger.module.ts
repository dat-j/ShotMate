import { randomUUID } from 'node:crypto';

import { LoggerModule as PinoLoggerModule } from 'nestjs-pino';
import type { IncomingMessage } from 'node:http';

/**
 * Structured JSON logging (pino) qua nestjs-pino + pino-http (spec FR-S4-6).
 *
 * Bảo mật (security.md, CWE-532 log của thông tin nhạy cảm):
 *  - redact `email` ở request body (POST /auth/magic-link) và response body
 *    (VerifyResult.user.email, MeResult.user.email) — PII duy nhất trong hệ
 *    thống.
 *  - redact `Authorization` header (JWT access token / RevenueCat webhook
 *    secret) và mọi trường token trong body (refreshToken, accessToken).
 *  - KHÔNG log base64 ảnh — base64 chỉ tồn tại ở tầng worker/AI provider
 *    (review.processor.ts, claude.provider.ts), không đi qua HTTP request
 *    logger này nên không cần redact riêng, nhưng path được thêm phòng thủ
 *    theo chiều sâu (defense in depth) nếu sau này lộ qua endpoint khác.
 *
 * Request-id: pino-http tự sinh `req.id` (uuid) cho mỗi request và đính kèm
 * vào mọi log line trong lifecycle của request đó — không cần middleware
 * riêng.
 *
 * Logger service-layer (`new Logger(...)` từ @nestjs/common trong
 * auth.service.ts, analysis.service.ts, v.v.) KHÔNG bị đổi — module này chỉ
 * cấu hình logger ở tầng HTTP/bootstrap.
 */
export const LoggerModule = PinoLoggerModule.forRoot({
  pinoHttp: {
    genReqId: (req: IncomingMessage) =>
      (req.headers['x-request-id'] as string | undefined) ?? randomUUID(),
    redact: {
      paths: [
        'req.headers.authorization',
        'req.headers.cookie',
        'req.body.email',
        'req.body.token',
        'req.body.refreshToken',
        'req.body.accessToken',
        'res.body.user.email',
        'res.body.accessToken',
        'res.body.refreshToken',
      ],
      censor: '[REDACTED]',
    },
    // Level theo env; mặc định 'info' production, 'debug' khi LOG_LEVEL set.
    level: process.env.LOG_LEVEL ?? 'info',
    // Test/CI: tránh log rác khi chạy vitest (không ảnh hưởng unit test vì
    // module này không được import trong bất kỳ *.spec.ts nào).
    autoLogging: process.env.NODE_ENV !== 'test',
  },
});
