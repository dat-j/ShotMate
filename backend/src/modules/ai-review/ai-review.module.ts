import { Module } from '@nestjs/common';

import { AI_REVIEW_PROVIDERS, AiReviewProvider } from './ai-review.provider';
import { AiReviewService } from './ai-review.service';
import { ClaudeReviewProvider } from './claude.provider';
import { GeminiReviewProvider } from './gemini.provider';
import { VertexReviewProvider } from './vertex.provider';

@Module({
  providers: [
    ClaudeReviewProvider,
    GeminiReviewProvider,
    VertexReviewProvider,
    {
      provide: AI_REVIEW_PROVIDERS,
      useFactory: (
        claude: ClaudeReviewProvider,
        gemini: GeminiReviewProvider,
        vertex: VertexReviewProvider,
      ): AiReviewProvider[] => [claude, gemini, vertex],
      inject: [ClaudeReviewProvider, GeminiReviewProvider, VertexReviewProvider],
    },
    AiReviewService,
  ],
  exports: [AiReviewService],
})
export class AiReviewModule {}
