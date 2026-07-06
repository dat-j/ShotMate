import { IsOptional, IsString } from 'class-validator';

/**
 * Body cho POST /subscriptions/verify (spec FR-S3-5 fallback path).
 * appUserId = RevenueCat app user id (== User.id phía ShotMate — client gửi
 * uuid của chính nó làm RevenueCat appUserId).
 */
export class VerifySubscriptionDto {
  @IsOptional()
  @IsString()
  appUserId?: string;
}
