import Anthropic from '@anthropic-ai/sdk';
import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

import {
  AiReviewProvider,
  REVIEW_SYSTEM_PROMPT,
  ReviewContext,
  ReviewResult,
  reviewResultSchema,
} from './ai-review.provider';

/**
 * Claude vision review (ADR-0004).
 * Model qua env CLAUDE_REVIEW_MODEL — Haiku cho scoring rẻ,
 * Sonnet cho premium review sâu.
 */
@Injectable()
export class ClaudeReviewProvider implements AiReviewProvider {
  readonly name = 'claude' as const;

  private readonly client: Anthropic;
  private readonly model: string;

  constructor(config: ConfigService) {
    this.client = new Anthropic({
      apiKey: config.getOrThrow<string>('ANTHROPIC_API_KEY'),
    });
    this.model = config.get<string>('CLAUDE_REVIEW_MODEL') ?? 'claude-haiku-4-5';
  }

  async review(
    imageBase64: string,
    context: ReviewContext,
  ): Promise<ReviewResult> {
    const response = await this.client.messages.create({
      model: this.model,
      max_tokens: 1024,
      system: REVIEW_SYSTEM_PROMPT,
      messages: [
        {
          role: 'user',
          content: [
            {
              type: 'image',
              source: {
                type: 'base64',
                media_type: 'image/jpeg',
                data: imageBase64,
              },
            },
            {
              type: 'text',
              text: `Scene: ${context.sceneType ?? 'không rõ'}. Chấm ảnh này.`,
            },
          ],
        },
      ],
    });

    const text = response.content
      .filter((block): block is Anthropic.TextBlock => block.type === 'text')
      .map((block) => block.text)
      .join('');
    return reviewResultSchema.parse(JSON.parse(extractJson(text)));
  }
}

/** Model đôi khi bọc JSON trong ```json fence — bóc ra trước khi parse. */
export function extractJson(text: string): string {
  const fenced = /```(?:json)?\s*([\s\S]*?)```/.exec(text);
  return (fenced?.[1] ?? text).trim();
}
