import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';

import { AiReviewModule } from './modules/ai-review/ai-review.module';
import { AnalysisModule } from './modules/analysis/analysis.module';
import { AuthModule } from './modules/auth/auth.module';
import { CreditsModule } from './modules/credits/credits.module';
import { PhotosModule } from './modules/photos/photos.module';
import { SubscriptionsModule } from './modules/subscriptions/subscriptions.module';
import { UsersModule } from './modules/users/users.module';

@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true }),
    AuthModule,
    UsersModule,
    PhotosModule,
    AnalysisModule,
    AiReviewModule,
    CreditsModule,
    SubscriptionsModule,
  ],
})
export class AppModule {}
