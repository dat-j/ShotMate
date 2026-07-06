import { IsNotEmpty, IsString } from 'class-validator';

/** Body cho POST /auth/refresh (spec FR-S3-1, Rule 6). */
export class RefreshDto {
  @IsString()
  @IsNotEmpty()
  refreshToken!: string;
}
