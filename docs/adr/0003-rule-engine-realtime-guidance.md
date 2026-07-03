# ADR-0003: Rule engine deterministic cho realtime guidance — không LLM trong realtime loop

## Metadata

**Status:** Accepted · **Date:** 2026-07-03 · **Deciders:** Đạt Trần · **Tags:** ai, architecture, performance
**Related PRD:** [PRD-shotmate-mvp.md](../prd/PRD-shotmate-mvp.md) · **Supersedes:** N/A · **Superseded By:** N/A

**Tech Strategy:** ✅ Follows Golden Path

---

## Context

Sau khi native module trả về `FrameAnalysis` (landmarks, horizon angle, subject box, scene, exposure), hệ thống phải quyết định hint nào hiển thị: "Move left", "Tilt up 8°", "Raise chin"... Quyết định này chạy mỗi lần có kết quả detect mới (5–15 lần/giây) và phải xong trong ~5ms.

Câu hỏi: logic quyết định là rule-based, on-device LLM, hay cloud LLM?

---

## Decision Drivers

- Latency budget cho bước quyết định: ≤ 5ms (trong tổng 100ms)
- Chạy 5–15 lần/giây suốt session → chi phí per-call phải ≈ 0
- Hint sai làm mất niềm tin ngay → cần deterministic, unit-testable, tái lập được
- Pin/nhiệt đã căng vì detection — không còn budget cho inference thêm
- Kiến thức nhiếp ảnh cơ bản (thirds, horizon, headroom) là quy tắc thành văn — không cần model để "hiểu"

---

## Considered Options

### Option 1: Rule engine deterministic (pure Dart)

`FrameAnalysis` → hàm thuần → `List<CoachHint>` + rating. Threshold có hysteresis; prioritizer chọn max 2 hint. Tuning qua config (Remote Config sau này).

| Pros | Cons |
|------|------|
| < 1ms/lần, zero cost, zero network | Không "sáng tạo" — chỉ biết rule đã viết |
| Unit test 100%, tái lập được từng hint | Rule nhiều scene dần phình — cần cấu trúc tốt |
| Hot-tune threshold không cần model mới | Nuance thẩm mỹ (màu, cảm xúc) nằm ngoài khả năng |

### Option 2: On-device LLM/VLM nhỏ (Gemma-class)

Model ngôn ngữ-thị giác nhỏ chạy on-device sinh hint.

| Pros | Cons |
|------|------|
| Hint "tự nhiên", phủ case chưa viết rule | Inference 200ms–1s+/call → phá vỡ realtime hoàn toàn |
| | +1–4GB model size; pin/nhiệt tăng mạnh |
| | Non-deterministic — không test/tái lập được hint sai |

### Option 3: Cloud LLM realtime

Gửi analysis (hoặc frame) lên LLM API mỗi giây.

| Pros | Cons |
|------|------|
| Chất lượng ngôn ngữ tốt nhất | Round-trip 500ms–2s; chết khi offline (vi phạm NFR-4) |
| | Chi phí: 10 call/giây × session phút → không có model kinh doanh nào chịu nổi |
| | Gửi frame lên cloud vi phạm NFR-3 (privacy) |

---

## Decision Outcome

**Chosen Option:** Option 1 — Rule engine deterministic, pure Dart

**Rationale:** Chỉ Option 1 thoả đồng thời 4 driver đầu. Kiến thức composition/pose cơ bản là tri thức quy tắc — LLM không thêm giá trị ở tần suất realtime, chỉ thêm latency/cost/rủi ro. LLM vẫn có chỗ đúng của nó: **post-capture review** (ADR-0004) — nơi 1 call/ảnh, không realtime, ngôn ngữ tự nhiên là giá trị chính.

Phân công rõ: *rule engine = huấn luyện viên đứng cạnh (nhanh, ngắn gọn); cloud LLM = giáo viên chấm bài sau buổi tập (sâu, giải thích).*

### Quantified Impact

| Metric | Rule engine | On-device LLM | Cloud LLM |
|--------|-------------|---------------|-----------|
| Latency/quyết định | < 1ms | 200ms–1s | 500ms–2s |
| Chi phí/session 10 phút | $0 | $0 (pin cao) | ~$1–10 |
| Testability | Unit test full | Không | Không |

---

## Consequences

**Positive:**
- Guidance loop độc lập mạng, chi phí biên = 0, test coverage đo được
- Rule tuning = đổi threshold qua config — không cần release model

**Negative:**
- Mỗi scene mới (V2–V4) cần viết + test bộ rule mới (chi phí tuyến tính theo scene)
- Chất lượng hint trần ở mức "quy tắc nhiếp ảnh" — không có gu thẩm mỹ cá nhân hoá (để sau: học từ Feedback entity)

**Risks:**
- Rule dao động quanh threshold gây hint nhấp nháy → hysteresis (ngưỡng bật ≠ tắt) + debounce 500ms trong HintPrioritizer

---

## Validation

- [ ] Rule engine benchmark < 5ms p99 trên máy tầm trung
- [ ] Unit test coverage rule engine ≥ 90%
- [ ] Golden test: bộ `FrameAnalysis` fixture → hint kỳ vọng, chạy trong CI
- [x] Tech Strategy alignment confirmed

---

## Links

- [PRD](../prd/PRD-shotmate-mvp.md) · [ADR-0001](./0001-native-side-frame-processing.md) · [ADR-0004 Cloud AI](./0004-cloud-ai-provider-adapter.md)

---

## Changelog

| Date | Author | Change |
|------|--------|--------|
| 2026-07-03 | Đạt Trần | Initial draft |
