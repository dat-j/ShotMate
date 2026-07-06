import { IsEmail } from 'class-validator';

/** Body cho POST /auth/magic-link (spec FR-S3-1, Rule 6). */
export class MagicLinkDto {
  @IsEmail()
  email!: string;
}
