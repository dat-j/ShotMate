# PRD: ShotMate — AI Camera Coach (MVP)

<!--
Product Requirements Document
Filename: docs/prd/PRD-shotmate-mvp.md
Owner: Architect (/architect)
Handoff to: Architect (/architect), UI/UX Designer (/ui-ux-designer)
Related Skills: writing-prds, decomposing-tasks, requirements-analysis
-->

## Overview

**Status:** Approved
**Author:** Đạt Trần (tranxuandat.dev@gmail.com)
**Date:** 2026-07-03
**Version:** 1.0
**Beads Issue:** N/A
**PR-FAQ:** N/A (bootstrap từ brainstorm session)
**Stakeholders:** Founder/Dev (Đạt)

## Problem Statement

Người dùng smartphone biết *chụp* ảnh nhưng không biết **đứng đâu, cầm máy thế nào, zoom bao nhiêu, bố cục ra sao**. Kết quả: ảnh du lịch, ảnh couple, ảnh đồ ăn ra đời hàng loạt nhưng xấu, và người chụp không biết vì sao xấu.

Toàn bộ app "AI camera" hiện có trên App Store / Play Store giải quyết **sau khi chụp** (edit, filter, remove object, replace sky). Không app phổ biến nào hướng dẫn **trước khi bấm nút** theo thời gian thực.

ShotMate lấp khoảng trống đó: một "nhiếp ảnh gia AI đứng cạnh bạn" — realtime guidance dưới 100ms, chạy on-device:

> "Lùi thêm 30 cm." / "Chuyển sang 2x." / "Nghiêng điện thoại 5°." / "Giơ cằm lên một chút." / "Đợi 5 giây nữa ánh sáng đẹp hơn."

### Evidence

**Quantitative Evidence** (cần validate ở beta — đây là giả thuyết ban đầu):
- Thị trường photo app thuộc nhóm lớn nhất trên cả 2 store; hầu hết tập trung vào post-processing → khoảng trống pre-capture guidance
- Người dùng phổ thông chụp trung bình nhiều lần cho 1 tấm ưng ý (retake nhiều lần) → thời gian + dung lượng lãng phí, trải nghiệm ức chế
- Nhóm seller (Shopee/TikTok Shop) chụp sản phẩm hàng ngày nhưng không có kỹ năng nhiếp ảnh — ảnh xấu ảnh hưởng trực tiếp conversion

**Qualitative Evidence:**
- Pain phổ biến: "chụp hộ tao với, mà chụp kiểu gì cho đẹp?" — người cầm máy không biết hướng dẫn
- Feedback sau khi chụp (app chấm điểm) không giúp được vì khoảnh khắc đã trôi qua — "giám khảo đến muộn"
- Kèm người thật (nhiếp ảnh gia) thì đắt và không scale

## Goals & Success Metrics

| Goal | Metric | Target |
|------|--------|--------|
| Guidance realtime mượt | Overlay update latency (frame → hint hiển thị) | < 100ms p90 |
| Guidance hữu ích | % ảnh chụp có score ≥ 80 khi làm theo hint | > 60% |
| Retention | D7 retention | > 20% |
| Engagement | Số ảnh chụp qua app / user / tuần | ≥ 10 |
| Monetization | Free → Premium conversion | ≥ 2% sau 3 tháng |
| Ổn định | Crash-free session rate | > 99.5% |
| Nhiệt/pin | Session 10 phút không thermal throttle trên máy tầm trung | Pass |

## User Stories

<!-- INVEST criteria -->

### Persona 1: Người dùng phổ thông 18–35 (du lịch, cafe, couple, TikTok/Instagram)

- As a traveler, I want app chỉ tôi đứng đâu và nghiêng máy bao nhiêu so that ảnh check-in có bố cục đẹp ngay lần chụp đầu
  - Acceptance: mở camera → overlay hiện hint di chuyển (trái/phải/lùi/tiến) + độ nghiêng, cập nhật < 100ms
- As a user chụp bạn bè, I want hướng dẫn pose (giơ cằm, xoay người, cười) so that người được chụp biết phải làm gì
  - Acceptance: khi có người trong khung hình, skeleton được detect và tối đa 1–2 hint pose hiển thị cùng lúc
- As a user, I want điểm số ảnh ngay sau khi chụp so that tôi biết ảnh đạt chưa hay cần chụp lại
  - Acceptance: sau capture < 2s hiển thị score 4 chiều (Composition / Lighting / Focus / Background), offline

### Persona 2: Creator (giai đoạn 2)

- As a creator, I want chế độ chuyên biệt theo loại cảnh (portrait/food/landscape) so that hint đúng ngữ cảnh content tôi làm
  - Acceptance: scene được tự phân loại, bộ rule guidance đổi theo scene
- As a creator, I want AI review chi tiết kèm giải thích so that tôi học được cách chụp tốt hơn qua từng tấm
  - Acceptance: (Premium, Sprint 3) ảnh đã chụp được cloud AI phân tích, trả về giải thích bằng ngôn ngữ tự nhiên

### Persona 3: Seller Shopee/TikTok Shop (giai đoạn 3 — ngoài MVP)

- As a seller, I want Product Mode hướng dẫn góc chụp sản phẩm so that ảnh listing tăng conversion
  - Acceptance: (V4) — ghi nhận để thiết kế data model không khoá cứng vào portrait

## Requirements

### Functional Requirements

| ID | Requirement | Priority | Notes |
|----|-------------|----------|-------|
| FR-1 | **Live Composition**: detect horizon, subject, rule of thirds, leading line, symmetry; hiển thị hint hướng di chuyển + rating sao realtime | Must Have | Sprint 1 (horizon + rule of thirds trước) |
| FR-2 | **Zoom Suggestion**: gợi ý mức zoom (0.5x/1x/1.5x/2x) theo scene (landscape/portrait/food) | Must Have | Sprint 2; cần scene classification |
| FR-3 | **Pose Guide**: detect skeleton người được chụp, overlay hint (raise chin, move right, smile) | Must Have | Sprint 1 detect, Sprint 2 hint |
| FR-4 | **Distance Guide**: cảnh báo quá gần/quá xa, gợi ý khoảng cách cụ thể (cm) | Must Have | Sprint 2; ước lượng từ kích thước subject trong khung |
| FR-5 | **Angle Guide**: gợi ý tilt up/down theo độ (dùng gyroscope + horizon detection) | Must Have | Sprint 2 |
| FR-6 | **Smart Countdown**: phát hiện ánh sáng đang cải thiện, đếm ngược thời điểm chụp | Should Have | Sprint 2; dựa trên exposure/histogram trend |
| FR-7 | **Photo Score**: chấm điểm sau chụp 4 chiều: Composition, Lighting, Focus, Background (0–100) | Must Have | Sprint 1 bản cơ bản, offline rule-based |
| FR-8 | **History**: lưu ảnh + score + analysis local | Must Have | Sprint 1–2 local (Drift); Sprint 3 sync |
| FR-9 | **Cloud AI Review**: phân tích sâu + giải thích ngôn ngữ tự nhiên cho ảnh đã chụp | Should Have | Sprint 3; Claude + Gemini Flash qua adapter; không realtime |
| FR-10 | **Account & Sync**: đăng nhập, đồng bộ history đa thiết bị | Should Have | Sprint 3 |
| FR-11 | **Subscription**: Free 10 phân tích/ngày; Premium unlimited + tính năng nâng cao | Should Have | Sprint 3; MVP enforce device-local |
| FR-12 | **Credit tracking**: đếm số lần phân tích/ngày, reset 00:00 local time | Must Have | Device-local trước, server-side Sprint 3 |

### Non-Functional Requirements

| ID | Requirement | Target |
|----|-------------|--------|
| NFR-1 | Overlay latency (frame in → hint render) | < 100ms p90 trên máy tầm trung (Snapdragon 7 series / A14 trở lên) |
| NFR-2 | Battery/thermal | 10 phút camera session không thermal throttling; adaptive throttling: pose ~15fps, composition ~5fps, scene classify ~1fps |
| NFR-3 | Privacy | Frame KHÔNG rời thiết bị. Chỉ ảnh đã chụp mới upload cho cloud review, và phải opt-in. App Store privacy label phản ánh đúng |
| NFR-4 | Offline-first | Toàn bộ realtime guidance + basic score hoạt động không cần mạng |
| NFR-5 | App size | < 150MB sau khi bundle model on-device |
| NFR-6 | Crash-free | > 99.5% sessions (Crashlytics) |
| NFR-7 | Cloud review latency | < 10s p90 từ lúc submit ảnh (Sprint 3) |
| NFR-8 | Cloud AI cost | Kiểm soát bằng credit + resize ảnh trước upload (max 1568px cạnh dài) |

## Scope

### In Scope (MVP = Sprint 1–3)

- Flutter app iOS + Android, camera realtime guidance (FR-1..FR-7)
- Rule engine deterministic on-device (không LLM realtime)
- Local history + score (offline)
- Backend NestJS (Sprint 3): auth, sync, subscription, cloud AI review
- Scene categories V1: Landscape, Portrait, Food

### Out of Scope (explicit non-goals)

- ❌ AI edit ảnh (chỉnh màu, retouch)
- ❌ AI remove people/objects
- ❌ AI filter
- ❌ AI replace sky
- ❌ Bất kỳ tính năng "Photoshop" nào
- ❌ Video coaching (chỉ ảnh tĩnh trong MVP)
- ❌ Social/feed/chia sẻ trong app
- ❌ Scene categories V2–V4 (Pet/Car/House, Travel/Wedding/Baby, Product/Fashion)

## Dependencies

| Dependency | Owner | Status | Risk |
|------------|-------|--------|------|
| MediaPipe Pose (on-device) | Đạt | Đã chọn (ADR-0006) | Low |
| Google ML Kit (face/object/labeling) | Đạt | Đã chọn (ADR-0006) | Low |
| Claude API + Gemini API (cloud review) | Đạt | Adapter 2 provider (ADR-0004) | Medium — cost/quota |
| Firebase (Analytics/Crashlytics/Remote Config) | Đạt | Sprint 1 setup | Low |
| Apple/Google developer accounts + IAP | Đạt | Cần trước Sprint 3 | Medium — review time |
| GCP project (Cloud Run/SQL/Storage) | Đạt | Sprint 3 | Low |

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Không đạt <100ms trên máy tầm trung | M | H | Xử lý frame ở native side (ADR-0001), throttling per-detector, đo benchmark ngay Sprint 1 tuần 1 — đây là go/no-go gate |
| Máy nóng/tụt pin làm user bỏ app | M | H | Adaptive throttling (NFR-2), giảm resolution frame phân tích (640px), tắt detector không cần theo scene |
| Hint quá nhiều gây rối (UX overload) | H | H | Tối đa 1–2 hint cùng lúc, ưu tiên theo severity; UX test sớm ở beta |
| Guidance sai (hint ngược, score vô lý) làm mất niềm tin | M | H | Rule engine pure Dart có unit test đầy đủ; golden test set ảnh mẫu; feedback button trên mỗi hint |
| Cloud AI cost vượt kiểm soát | M | M | Credit limit, resize ảnh, chọn provider rẻ theo Remote Config (Claude Haiku / Gemini Flash), cache kết quả |
| Free tier bypass (device-local) | H | L | Chấp nhận ở MVP; enforce server-side Sprint 3 |
| Apple/Google từ chối app (camera + AI claims) | L | H | Privacy label chuẩn, không thu frame, review guideline trước submit |

## Open Questions

- [ ] Giá Premium: $x.99/tháng? Cần khảo giá competitor trước Sprint 3
- [ ] Có cần Android Go / máy yếu fallback mode (chỉ composition, tắt pose)?
- [ ] Tên chính thức "ShotMate" — check trademark + tên khả dụng trên 2 store
- [ ] RevenueCat hay IAP native trực tiếp cho subscription? (đề xuất: RevenueCat để đỡ maintain 2 store logic)

## Appendix

### Mockups/Wireframes

Concept overlay (từ brainstorm):

```
┌──────────────────────┐
│  ⭐⭐⭐⭐☆            │  ← composition rating realtime
│                      │
│    [camera preview]  │
│    ┆    ┆    ┆       │  ← rule-of-thirds grid
│                      │
│   ⬅️ Move Left        │  ← tối đa 1–2 hint
│   📐 Tilt up 8°       │
└──────────────────────┘
```

Score screen sau chụp:

```
Composition  95
Lighting     90
Focus       100
Background   72
```

### Research

- Competitive gap: các app photo AI phổ biến đều là post-capture editing → pre-capture coaching là khoảng trống
- Naming candidates đã cân nhắc: SnapCoach AI, FrameWise, ShotMate ✅, PhotoPilot AI, LensGuide AI

---

## Approval

| Role | Name | Date | Status |
|------|------|------|--------|
| Product | Đạt Trần | 2026-07-03 | Approved |
| Engineering | Đạt Trần | 2026-07-03 | Approved |
| Design | — | | Pending |

---

## Next Steps & Handoffs

After PRD approval:

1. [x] **Architect Review**: `docs/adr/0001..0006` + `docs/design/system-design-shotmate.md`
2. [ ] **UI/UX Designer**: Design Spec cho camera overlay UX (Sprint 1)
3. [x] **Engineering Estimate**: `docs/roadmap.md` (3 sprint × 2 tuần)
4. [ ] **Create Beads Issues**: decompose Sprint 1 từ `docs/specs/spec-sprint-1.md`

**Related Artifacts**:
- ADR: [0001](../adr/0001-native-side-frame-processing.md) · [0002](../adr/0002-offline-first-backend-sprint-3.md) · [0003](../adr/0003-rule-engine-realtime-guidance.md) · [0004](../adr/0004-cloud-ai-provider-adapter.md) · [0005](../adr/0005-local-storage-drift.md) · [0006](../adr/0006-on-device-ml-stack.md)
- System Design: [system-design-shotmate.md](../design/system-design-shotmate.md)
- Spec Sprint 1: [spec-sprint-1.md](../specs/spec-sprint-1.md)
- Roadmap: [roadmap.md](../roadmap.md)

---

## Version History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-07-03 | Đạt Trần | Initial draft từ brainstorm session |
