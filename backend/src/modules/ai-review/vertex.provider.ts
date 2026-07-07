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
 * Gemini qua Vertex AI (ADR-0004 mở rộng) — cùng model Gemini nhưng billing
 * tính thẳng vào GCP project (Cloud Billing) thay vì prepayment credit riêng
 * của Google AI Studio (nguồn gốc lỗi 429 RESOURCE_EXHAUSTED của
 * GeminiReviewProvider khi credit AI Studio cạn). Dùng Application Default
 * Credentials (service account Cloud Run) — không cần API key.
 */
@Injectable()
export class VertexReviewProvider implements AiReviewProvider {
  readonly name = 'vertex' as const;

  private readonly client: GoogleGenAI;
  private readonly model: string;

  constructor(config: ConfigService) {
    this.client = new GoogleGenAI({
      vertexai: true,
      project: config.getOrThrow<string>('VERTEX_PROJECT_ID'),
      location: config.get<string>('VERTEX_LOCATION') ?? 'us-central1',
    });
    this.model = config.get<string>('VERTEX_REVIEW_MODEL') ?? 'gemini-2.5-flash';
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
