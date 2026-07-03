import { Module } from '@nestjs/common';

import { AI_REVIEW_PROVIDERS, AiReviewProvider } from './ai-review.provider';
import { AiReviewService } from './ai-review.service';
import { ClaudeReviewProvider } from './claude.provider';
import { GeminiReviewProvider } from './gemini.provider';

@Module({
  providers: [
    ClaudeReviewProvider,
    GeminiReviewProvider,
    {
      provide: AI_REVIEW_PROVIDERS,
      useFactory: (
        claude: ClaudeReviewProvider,
        gemini: GeminiReviewProvider,
      ): AiReviewProvider[] => [claude, gemini],
      inject: [ClaudeReviewProvider, GeminiReviewProvider],
    },
    AiReviewService,
  ],
  exports: [AiReviewService],
})
export class AiReviewModule {}
