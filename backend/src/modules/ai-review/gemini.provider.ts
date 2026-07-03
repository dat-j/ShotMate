import { GoogleGenAI } from '@google/genai';
import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

import {
  AiReviewProvider,
  REVIEW_SYSTEM_PROMPT,
  ReviewContext,
  ReviewResult,
  reviewResultSchema,
} from './ai-review.provider';
import { extractJson } from './claude.provider';

/**
 * Gemini Flash vision review (ADR-0004) — provider chi phí thấp,
 * cùng hệ sinh thái GCP. Model qua env GEMINI_REVIEW_MODEL.
 */
@Injectable()
export class GeminiReviewProvider implements AiReviewProvider {
  readonly name = 'gemini' as const;

  private readonly client: GoogleGenAI;
  private readonly model: string;

  constructor(config: ConfigService) {
    this.client = new GoogleGenAI({
      apiKey: config.getOrThrow<string>('GEMINI_API_KEY'),
    });
    this.model = config.get<string>('GEMINI_REVIEW_MODEL') ?? 'gemini-2.5-flash';
  }

  async review(
    imageBase64: string,
    context: ReviewContext,
  ): Promise<ReviewResult> {
    const response = await this.client.models.generateContent({
      model: this.model,
      contents: [
        {
          role: 'user',
          parts: [
            { inlineData: { mimeType: 'image/jpeg', data: imageBase64 } },
            {
              text: `${REVIEW_SYSTEM_PROMPT}\n\nScene: ${context.sceneType ?? 'không rõ'}. Chấm ảnh này.`,
            },
          ],
        },
      ],
    });

    return reviewResultSchema.parse(JSON.parse(extractJson(response.text ?? '')));
  }
}
