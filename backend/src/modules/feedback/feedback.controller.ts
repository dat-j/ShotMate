import { Body, Controller, HttpCode, Post } from '@nestjs/common';

import { AuthUser, CurrentUser } from '../../common/auth/current-user.decorator';
import { FeedbackDto } from './dto/feedback.dto';
import { FeedbackService } from './feedback.service';

/** FeedbackController — POST /feedback (spec FR-S3-10). Authenticated (guard global). */
@Controller('feedback')
export class FeedbackController {
  constructor(private readonly feedback: FeedbackService) {}

  @Post()
  @HttpCode(201)
  create(
    @CurrentUser() user: AuthUser,
    @Body() dto: FeedbackDto,
  ): Promise<{ id: string }> {
    return this.feedback.create(user.userId, dto);
  }
}
