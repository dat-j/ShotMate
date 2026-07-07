/**
 * AiReviewProvider — contract chung cho mọi cloud AI review (ADR-0004).
 *
 * Cả Claude và Gemini implement interface này; AiReviewService chọn provider
 * theo config và failover khi lỗi. Output validate bằng zod trước khi lưu —
 * KHÔNG tin raw LLM output.
 */
import { z } from 'zod';

export const reviewResultSchema = z.object({
  scores: z.object({
    composition: z.number().int().min(0).max(100),
    lighting: z.number().int().min(0).max(100),
    focus: z.number().int().min(0).max(100),
    background: z.number().int().min(0).max(100),
  }),
  /** Giải thích ngôn ngữ tự nhiên, tiếng Việt. */
  explanation: z.string().min(1),
  /** Gợi ý cải thiện cụ thể, hành động được. */
  suggestions: z.array(z.string()).max(5),
});

export type ReviewResult = z.infer<typeof reviewResultSchema>;

export interface ReviewContext {
  /** landscape | portrait | food — từ on-device scene classifier. */
  sceneType?: string;
  /** Score on-device để model đối chiếu (không bắt buộc theo). */
  onDeviceScores?: ReviewResult['scores'];
  /** vi (mặc định) — chuẩn bị cho i18n sau. */
  locale?: string;
}

export interface AiReviewProvider {
  readonly name: 'claude' | 'gemini' | 'vertex';

  /**
   * @param imageBase64 ảnh JPEG đã resize ≤1568px cạnh dài (client làm)
   * @throws lỗi provider (rate limit, timeout...) — service bắt để failover
   */
  review(imageBase64: string, context: ReviewContext): Promise<ReviewResult>;
}

export const AI_REVIEW_PROVIDERS = Symbol('AI_REVIEW_PROVIDERS');

/** Prompt dùng chung 2 provider — giữ một chỗ để so sánh công bằng khi benchmark. */
export const REVIEW_SYSTEM_PROMPT = `Bạn là nhiếp ảnh gia chuyên nghiệp, chấm ảnh cho người dùng phổ thông Việt Nam.
Chấm 4 chiều (0-100): composition, lighting, focus, background.
Giải thích ngắn gọn, thân thiện, KHÔNG dùng thuật ngữ khó. Tối đa 5 gợi ý cải thiện, mỗi gợi ý là một hành động cụ thể làm được ngay lần chụp sau.
Trả về DUY NHẤT một JSON object: {"scores":{"composition":n,"lighting":n,"focus":n,"background":n},"explanation":"...","suggestions":["..."]}`;
