import { Controller, Delete, Get, HttpCode } from '@nestjs/common';

import { AuthUser, CurrentUser } from '../../common/auth/current-user.decorator';
import { MeResult, UsersService } from './users.service';

/** Account management (spec FR-S3-7): GET/DELETE /me. Auth bắt buộc (guard global). */
@Controller('me')
export class UsersController {
  constructor(private readonly users: UsersService) {}

  @Get()
  getMe(@CurrentUser() user: AuthUser): Promise<MeResult> {
    return this.users.getMe(user.userId);
  }

  @Delete()
  @HttpCode(204)
  deleteMe(@CurrentUser() user: AuthUser): Promise<void> {
    return this.users.deleteMe(user.userId);
  }
}
