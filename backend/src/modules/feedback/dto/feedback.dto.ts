import { IsIn, IsOptional, IsString, MaxLength } from 'class-validator';

/** Body cho POST /feedback (spec FR-S3-10). Offline → app bỏ qua im lặng. */
export class FeedbackDto {
  @IsIn(['hint', 'score', 'review'])
  targetKind!: 'hint' | 'score' | 'review';

  @IsString()
  targetRef!: string;

  @IsIn([1, -1])
  rating!: 1 | -1;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  comment?: string;
}
