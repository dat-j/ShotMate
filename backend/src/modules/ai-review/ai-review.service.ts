import { Inject, Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

import {
  AI_REVIEW_PROVIDERS,
  AiReviewProvider,
  ReviewContext,
  ReviewResult,
} from './ai-review.provider';

/**
 * Chọn provider theo config + failover tự động (ADR-0004).
 *
 * AI_REVIEW_PRIMARY = 'claude' | 'gemini' (env; Sprint 3: đọc từ Remote
 * Config để switch không cần deploy). Primary lỗi → thử lần lượt provider
 * còn lại; tất cả lỗi → ném lỗi cuối để worker retry theo backoff của BullMQ.
 */
@Injectable()
export class AiReviewService {
  private readonly logger = new Logger(AiReviewService.name);

  constructor(
    @Inject(AI_REVIEW_PROVIDERS)
    private readonly providers: AiReviewProvider[],
    private readonly config: ConfigService,
  ) {}

  async review(
    imageBase64: string,
    context: ReviewContext,
  ): Promise<ReviewResult & { provider: AiReviewProvider['name'] }> {
    const primary = this.config.get<string>('AI_REVIEW_PRIMARY') ?? 'claude';
    const ordered = [...this.providers].sort((a, b) =>
      a.name === primary ? -1 : b.name === primary ? 1 : 0,
    );

    let lastError: unknown;
    for (const provider of ordered) {
      try {
        const result = await provider.review(imageBase64, context);
        return { ...result, provider: provider.name };
      } catch (error) {
        lastError = error;
        this.logger.warn(
          `Provider ${provider.name} failed, failing over: ${String(error)}`,
        );
      }
    }
    throw lastError;
  }
}
