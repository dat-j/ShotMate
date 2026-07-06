import { IsNotEmpty, IsString } from 'class-validator';

/** Body cho POST /auth/verify (spec FR-S3-1, Rule 6). */
export class VerifyDto {
  @IsString()
  @IsNotEmpty()
  token!: string;
}
