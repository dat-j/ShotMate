import { Type } from 'class-transformer';
import { IsInt, IsISO8601, IsOptional, Max, Min } from 'class-validator';

/**
 * Query cho GET /sync/photos (spec FR-S3-6 pull chiều về). Cursor-based
 * theo taken_at DESC — cursor là ISO timestamp của bản ghi cuối cùng đã nhận.
 */
export class PullPhotosQueryDto {
  @IsOptional()
  @IsISO8601()
  cursor?: string;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(100)
  limit?: number;
}
