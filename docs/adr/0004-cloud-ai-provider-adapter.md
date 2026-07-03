# ADR-0004: Cloud AI review qua provider adapter — tích hợp cả Claude và Gemini Flash

## Metadata

**Status:** Accepted · **Date:** 2026-07-03 · **Deciders:** Đạt Trần · **Tags:** ai, backend, cost
**Related PRD:** [PRD-shotmate-mvp.md](../prd/PRD-shotmate-mvp.md) · **Supersedes:** N/A · **Superseded By:** N/A

**Tech Strategy:** ✅ Follows Golden Path

---

## Context

Post-capture, user (Premium hoặc trong quota free) gửi ảnh lên cloud để AI phân tích sâu: score 4 chiều + giải thích ngôn ngữ tự nhiên + gợi ý cải thiện (FR-9). Đây là chi phí biến đổi lớn nhất của hệ thống và là feature ăn tiền chính của Premium.

Chưa có dữ liệu benchmark ảnh thật để biết provider nào cho chất lượng review/giá tốt nhất cho use case tiếng Việt + nhiếp ảnh.

---

## Decision Drivers

- Chất lượng giải thích tiếng Việt tự nhiên, đúng chuyên môn nhiếp ảnh
- Chi phí/ảnh phải khớp model kinh doanh (free 10 ảnh/ngày là loss leader)
- Không vendor lock-in — giá/quota/chính sách API thay đổi thường xuyên
- Đổi provider không cần release app (server-side switch)
- Solo dev: 2 tích hợp là trần maintain được

---

## Considered Options

### Option 1: Một provider duy nhất (chọn ngay)

Chọn 1 trong Claude/Gemini/GPT từ đầu.

| Pros | Cons |
|------|------|
| Ít code nhất, 1 prompt để tune | Chọn khi chưa có benchmark = đoán |
| | Lock-in; provider down = feature down |

### Option 2: Adapter interface, tích hợp cả Claude và Gemini Flash

`AiReviewProvider` interface (NestJS): `review(image, context) → ReviewResult` chuẩn hoá. Hai implementation: `ClaudeReviewProvider` (Claude Haiku mặc định cho scoring, Sonnet cho premium review sâu), `GeminiReviewProvider` (Gemini Flash). Chọn provider per-request qua config/Remote Config; failover tự động khi provider lỗi.

| Pros | Cons |
|------|------|
| Benchmark bằng traffic thật (A/B qua Remote Config) | 2 prompt phải maintain song song |
| Failover: 1 provider down, review vẫn chạy | Chuẩn hoá output 2 model về 1 schema cần json-schema validation |
| Đàm phán giá/đổi provider = đổi config | +~2 ngày effort so với Option 1 |

### Option 3: LLM gateway bên thứ ba (OpenRouter/LiteLLM)

| Pros | Cons |
|------|------|
| N provider qua 1 API | Thêm 1 hop latency + 1 bên thứ ba thấy ảnh user (privacy) |
| | Phụ thuộc uptime + margin của gateway |

---

## Decision Outcome

**Chosen Option:** Option 2 — Adapter với 2 provider: Claude + Gemini Flash

**Rationale:** User đã chốt tích hợp cả hai. Adapter cho phép quyết định bằng dữ liệu (chất lượng review tiếng Việt, cost thật/ảnh, latency) thay vì đoán; failover giải quyết availability; Remote Config switch giải quyết "đổi không cần release". Option 3 bị loại vì ảnh user đi qua bên thứ ba là rủi ro privacy không cần thiết. Ảnh resize client-side ≤1568px cạnh dài trước upload để tối ưu token vision cả 2 provider.

### Quantified Impact (ước tính, cần benchmark thật ở Sprint 3)

| Metric | Claude Haiku | Gemini Flash | Notes |
|--------|--------------|--------------|-------|
| Cost/ảnh review (ước) | ~$0.002–0.01 | ~$0.001–0.005 | Ảnh 1568px + ~500 token output |
| Latency p90 | 3–8s | 2–6s | Trong budget <10s (NFR-7) |
| Failover coverage | 2 provider → gần như luôn có 1 sống | | |

---

## Consequences

**Positive:**
- Không bao giờ bị 1 vendor giữ con tin về giá; A/B chất lượng bằng Feedback entity (user rate review)
- Prompt + output schema versioned trong repo → review reproducible

**Negative:**
- Mọi thay đổi output schema phải test trên cả 2 provider
- Chi phí prompt engineering ×2

**Risks:**
- Hai provider trả chất lượng lệch nhau → user experience không đồng nhất → mitigate: normalize score bằng calibration set (bộ ảnh mẫu chấm tay), điều chỉnh system prompt từng provider

---

## Validation

- [ ] Benchmark Sprint 3: 50 ảnh calibration set → so score/explanation 2 provider vs chấm tay
- [ ] Failover test: kill 1 provider key, review vẫn hoàn thành qua provider còn lại
- [ ] Cost/ảnh đo thật ≤ $0.01
- [x] Tech Strategy alignment confirmed

---

## Links

- [PRD FR-9](../prd/PRD-shotmate-mvp.md) · [System Design §3 Backend Components](../design/system-design-shotmate.md) · [ADR-0003](./0003-rule-engine-realtime-guidance.md)

---

## Changelog

| Date | Author | Change |
|------|--------|--------|
| 2026-07-03 | Đạt Trần | Initial draft |
