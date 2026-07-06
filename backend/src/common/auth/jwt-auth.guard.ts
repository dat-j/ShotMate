import {
  CanActivate,
  ExecutionContext,
  Injectable,
} from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { Reflector } from '@nestjs/core';
import type { FastifyRequest } from 'fastify';

import { AppError } from '../http/http-error.filter';
import { AuthUser } from './current-user.decorator';
import { IS_PUBLIC_KEY } from './public.decorator';

/**
 * Guard JWT global. Route @Public() bỏ qua. Access token payload:
 * { sub: userId, plan } (spec FR-S3-1). Sai/thiếu token → 401 AUTH_TOKEN_INVALID.
 */
@Injectable()
export class JwtAuthGuard implements CanActivate {
  constructor(
    private readonly jwt: JwtService,
    private readonly reflector: Reflector,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const isPublic = this.reflector.getAllAndOverride<boolean>(IS_PUBLIC_KEY, [
      context.getHandler(),
      context.getClass(),
    ]);
    if (isPublic) return true;

    const req = context
      .switchToHttp()
      .getRequest<FastifyRequest & { user?: AuthUser }>();
    const header = req.headers.authorization;
    if (!header?.startsWith('Bearer ')) {
      throw new AppError(401, 'AUTH_TOKEN_INVALID', 'Missing bearer token');
    }
    const token = header.slice('Bearer '.length);
    try {
      const payload = await this.jwt.verifyAsync<{ sub: string; plan?: string }>(
        token,
      );
      req.user = { userId: payload.sub, plan: payload.plan ?? 'free' };
      return true;
    } catch {
      throw new AppError(401, 'AUTH_TOKEN_INVALID', 'Invalid or expired token');
    }
  }
}
