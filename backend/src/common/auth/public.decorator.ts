import { SetMetadata } from '@nestjs/common';

/** Đánh dấu route bỏ qua JwtAuthGuard (auth endpoints, healthz, webhook). */
export const IS_PUBLIC_KEY = 'isPublic';
export const Public = (): MethodDecorator & ClassDecorator =>
  SetMetadata(IS_PUBLIC_KEY, true);
