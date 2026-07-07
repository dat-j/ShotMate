import {
  CanActivate,
  ExecutionContext,
  Injectable,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import type { FastifyRequest } from 'fastify';

import { AppError } from '../http/http-error.filter';
import { AuthUser } from '../auth/current-user.decorator';
import { RATE_LIMIT_KEY, RateLimitRule } from './rate-limit.decorator';
import { RateLimitService } from './rate-limit.service';

/** Toàn API authenticated — 60 req/phút/user (FR-S4-4 bảng scope, hàng 3). */
const AUTHENTICATED_DEFAULT_RULE: RateLimitRule = {
  name: 'authenticated-default',
  limit: 60,
  windowSeconds: 60,
  keyBy: 'user',
};

/**
 * RateLimitGuard — global (APP_GUARD). Luôn áp `AUTHENTICATED_DEFAULT_RULE`
 * cho request đã có `req.user` (set bởi `JwtAuthGuard` chạy trước — thứ tự
 * providers trong AppModule), CỘNG với rule bổ sung gắn qua `@RateLimit()`
 * trên route cụ thể (vd magic-link email+IP, review 10/user/phút) — spec
 * bảng FR-S4-4 là các tầng cộng dồn, không thay thế nhau.
 *
 * Route public (`@Public()`, không có `req.user`) chỉ chịu rule tường minh
 * (`@RateLimit()`), không bị default-user rule vì chưa có identity user.
 */
@Injectable()
export class RateLimitGuard implements CanActivate {
  constructor(
    private readonly reflector: Reflector,
    private readonly rateLimit: RateLimitService,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const routeRules =
      this.reflector.getAllAndOverride<RateLimitRule[] | undefined>(RATE_LIMIT_KEY, [
        context.getHandler(),
        context.getClass(),
      ]) ?? [];

    const req = context
      .switchToHttp()
      .getRequest<FastifyRequest & { user?: AuthUser }>();

    const rules = req.user
      ? [AUTHENTICATED_DEFAULT_RULE, ...routeRules]
      : routeRules;

    if (rules.length === 0) return true;

    for (const rule of rules) {
      const identity = this.resolveIdentity(rule, req);
      // Không resolve được identity (vd user chưa auth trên route email-only)
      // → bỏ qua rule đó, không chặn nhầm.
      if (identity === undefined) continue;

      const key = `ratelimit:${rule.name}:${identity}`;
      const result = await this.rateLimit.check({
        key,
        limit: rule.limit,
        windowSeconds: rule.windowSeconds,
      });

      if (!result.allowed) {
        throw new AppError(
          429,
          'RATE_LIMITED',
          `Too many requests — vui lòng thử lại sau (${rule.name}).`,
        );
      }
    }

    return true;
  }

  private resolveIdentity(
    rule: RateLimitRule,
    req: FastifyRequest & { user?: AuthUser },
  ): string | undefined {
    switch (rule.keyBy) {
      case 'ip':
        return req.ip;
      case 'user':
        return req.user?.userId;
      case 'email': {
        const body = req.body as { email?: unknown } | undefined;
        const email = typeof body?.email === 'string' ? body.email : undefined;
        return email ? email.trim().toLowerCase() : undefined;
      }
      default:
        return undefined;
    }
  }
}
