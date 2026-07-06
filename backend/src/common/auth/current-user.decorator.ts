import { createParamDecorator, ExecutionContext } from '@nestjs/common';
import type { FastifyRequest } from 'fastify';

/** Payload JWT gắn vào request bởi JwtAuthGuard. */
export interface AuthUser {
  userId: string;
  plan: string;
}

/**
 * @CurrentUser() — lấy user đã xác thực. Authorization thật LUÔN query DB
 * theo userId này; `plan` chỉ để hint, không tin tuyệt đối (spec FR-S3-1).
 */
export const CurrentUser = createParamDecorator(
  (_data: unknown, ctx: ExecutionContext): AuthUser => {
    const req = ctx.switchToHttp().getRequest<FastifyRequest & { user?: AuthUser }>();
    if (!req.user) {
      throw new Error('CurrentUser used on a route without JwtAuthGuard');
    }
    return req.user;
  },
);
