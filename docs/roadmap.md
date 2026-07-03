# Roadmap: ShotMate — AI Camera Coach

<!--
Project Roadmap
Filename: docs/roadmap.md
Owner: Architect (/architect)
Related Skills: execution-roadmaps, decomposing-tasks, estimating-work, agile-methodology
-->

## Overview

**Status:** Active
**Owner:** Đạt Trần
**Last Updated:** 2026-07-03 (Sprint 1 Dart layer hoàn thành)
**Beads Issue:** N/A
**Timeline:** 2026-07-07 → 2026-08-15 (MVP 3 sprint × 2 tuần) + V1–V4 sau beta

## Vision

Mỗi lần người dùng mở camera, họ có một nhiếp ảnh gia AI đứng cạnh: "Lùi 30cm", "Chuyển 2x", "Nghiêng 5°", "Giơ cằm lên" — tất cả trong <100ms, hoàn toàn on-device. ShotMate là app đầu tiên coach **trước khi bấm nút**, không phải editor đến muộn sau khi chụp. Mở rộng dần từ người dùng phổ thông (du lịch/couple/social) → creator → seller → ngành dọc (BĐS, xe, F&B).

## Goals

| Goal | Key Result | Status |
|------|------------|--------|
| Chứng minh realtime coaching khả thi | Frame→hint <100ms p90 trên Pixel 6a/iPhone 12 | Not Started |
| Beta với user thật | ≥ 50 beta testers, D7 retention > 20% | Not Started |
| Nền tảng doanh thu | Subscription live trên 2 store, conversion ≥ 2% | Not Started |

## Phases

### Phase 1: Sprint 1 — Foundation (Camera + Composition + Score)

**Timeline:** 2026-07-07 → 2026-07-18
**Status:** In Progress — Dart layer hoàn thành 2026-07-03 (commit `b5568dc`, 80/80 test pass, analyze 0 issue); còn native inference module + benchmark gate

**Deliverables:** (chi tiết: [spec-sprint-1.md](specs/spec-sprint-1.md), tiến độ: [sprint-1-status.md](specs/sprint-1-status.md))
- [x] Camera preview + overlay framework (grid, hints, rating) — Dart side xong; cần scaffold native runner (`flutter create`) để chạy trên thiết bị
- [ ] Native inference module: MediaPipe pose + composition analyzer + exposure sampler — **chưa bắt đầu** (android/ios mới có contract docs, chưa có project runner)
- [x] Rule engine v0 (horizon, thirds, subject size/cut) + HintPrioritizer — 13 golden test
- [x] Photo Score cơ bản 4 chiều (offline) + History (Drift) + Credit tracker — focus/background dùng placeholder chờ native detector
- [ ] Perf HUD + **benchmark gate <100ms (go/no-go)** — HUD + PerfTracker (p50/p90 sliding window) đã dựng xong phía Dart; gate chỉ đo được khi có native module + thiết bị tham chiếu

**Dependencies:** None

**Risks:**
- Benchmark fail trên máy tầm trung → hạ resolution phân tích/model lite hơn; nếu vẫn fail → xét lại kiến trúc (dừng lại thay vì ship trải nghiệm lag)

---

### Phase 2: Sprint 2 — Core Coaching (Pose/Zoom/Distance/Angle/Countdown)

**Timeline:** 2026-07-21 → 2026-08-01
**Status:** Not Started

**Deliverables:**
- [ ] Pose Guide hints (raise chin, move right, smile — max 2 hint rule)
- [ ] Scene classifier (landscape/portrait/food) → Zoom Suggestion (0.5x/1x/1.5x/2x)
- [ ] Distance Guide (quá gần/xa + cm ước lượng) + Angle Guide (tilt ±°)
- [ ] Smart Countdown theo lighting trend
- [ ] Photo Review screen hoàn chỉnh + Settings
- [ ] Thermal adaptive throttling hoàn thiện (EC-4)

**Dependencies:** Phase 1 complete (đặc biệt benchmark gate pass)

**Risks:**
- Scene classifier accuracy < 85% bằng ML Kit labeling → spike train TFLite classifier 3 lớp (đường thoát trong ADR-0006)
- Hint overload UX → user test nội bộ giữa sprint, cắt hint xuống theo severity

---

### Phase 3: Sprint 3 — Backend + Monetization + Beta

**Timeline:** 2026-08-04 → 2026-08-15
**Status:** Not Started

**Deliverables:**
- [ ] NestJS API trên Cloud Run: auth magic link + JWT, user, photos, sync
- [ ] Cloud AI review pipeline: BullMQ + `AiReviewProvider` (Claude + Gemini Flash, failover, Remote Config switch)
- [ ] Credits server-side + Subscription (IAP verify; quyết định RevenueCat trước sprint)
- [ ] Firebase Analytics dashboard + Crashlytics triage flow
- [ ] Beta: TestFlight + Play Internal track, 50 testers

**Dependencies:** Phase 2 complete; Apple/Google dev accounts + GCP project sẵn sàng **trước** sprint

**Risks:**
- Sprint dày nhất (đã biết trước — ADR-0002 đánh đổi có chủ đích) → nếu trễ, cắt sync đa thiết bị ra sau beta, giữ auth + review + subscription
- App review 2 store lâu → submit build từ giữa sprint

---

### Phase 4+: Post-MVP (V1 → V4)

**Timeline:** Sau beta, pace theo feedback
**Status:** Planning

| Version | Scene categories | Ghi chú |
|---------|------------------|---------|
| V1 (MVP) | Landscape, Portrait, Food | Trong Sprint 1–3 |
| V2 | Pet, Car, House | Rule set + classifier mở rộng |
| V3 | Travel, Wedding, Baby | Travel Mode premium |
| V4 | Product, Shopee, Fashion | Product Mode cho seller — bước vào thị trường B2B nhỏ |

---

## Milestones

| Milestone | Target Date | Status | Notes |
|-----------|-------------|--------|-------|
| Benchmark gate pass (<100ms) | 2026-07-11 | Pending | Go/no-go của cả sản phẩm — blocked bởi native module (chưa bắt đầu) |
| Sprint 1 done — app coach được composition | 2026-07-18 | In Progress | Dart layer xong 2026-07-03; còn native module + chạy thiết bị thật |
| Sprint 2 done — full coaching offline | 2026-08-01 | Pending | Airplane-mode demo được toàn bộ |
| Beta launch (TestFlight + Internal) | 2026-08-15 | Pending | |
| Public launch quyết định sau beta | TBD | Pending | Dựa trên D7 retention + feedback |

## Resource Allocation

| Phase | Engineering | Design | Product | QA |
|-------|-------------|--------|---------|-----|
| Phase 1 | 1 (Đạt) | 0.2 (Đạt) | 0.1 | kèm dev |
| Phase 2 | 1 | 0.3 (UX hint là trọng tâm) | 0.1 | kèm dev |
| Phase 3 | 1 | 0.1 | 0.2 (pricing/beta) | kèm dev |

> Solo dev — con số là tỷ trọng thời gian. Swarm workers (Claude Code) dùng để song song hoá: builder cho rule engine/backend module, reviewer cho security pass trước beta.

## Dependencies

```
Phase 1 ──────→ Phase 2 ──────→ Phase 3 ──────→ V2/V3/V4
   │                               ↑
   └── Benchmark gate          Store accounts + GCP project
```

| Dependency | Owner | Status | Risk Level |
|------------|-------|--------|------------|
| Thiết bị test tham chiếu (Pixel 6a, iPhone 12) | Đạt | Cần xác nhận | M |
| Apple Developer + Play Console accounts | Đạt | Cần trước Phase 3 | M |
| GCP project + billing | Đạt | Cần trước Phase 3 | L |
| Claude + Gemini API keys | Đạt | Cần trước Phase 3 | L |

## Risks & Mitigations

| Risk | Probability | Impact | Score | Mitigation | Owner |
|------|-------------|--------|-------|------------|-------|
| Latency gate fail | M | H | 6 | Model lite, hạ resolution, hạ fps; kiến trúc đã tối ưu sẵn (ADR-0001) | Đạt |
| Solo dev bandwidth / burnout | H | H | 9 | Offline-first cắt scope (ADR-0002); swarm workers; cắt sync nếu Sprint 3 trễ | Đạt |
| UX hint gây rối thay vì giúp | M | H | 6 | Max 2 hint + hysteresis (spec Rule 1–2); user test giữa Sprint 2 | Đạt |
| Store review chậm/từ chối | M | M | 4 | Privacy label chuẩn, submit sớm giữa Sprint 3 | Đạt |
| Cloud AI cost vượt dự kiến | M | M | 4 | Credit + resize + provider switch (ADR-0004) | Đạt |

## Communication Plan

| Audience | Frequency | Channel | Content |
|----------|-----------|---------|---------|
| Chính mình (solo) | Cuối mỗi sprint | Retro note trong docs/ | Gate pass/fail, scope quyết định |
| Beta testers | Hàng tuần (Phase 3+) | TestFlight notes / group chat | Changelog + câu hỏi feedback |

## Success Criteria

### Launch Readiness (beta)

- [ ] Toàn bộ acceptance criteria spec Sprint 1–2 pass
- [ ] Benchmark <100ms + thermal 10 phút pass trên 2 thiết bị tham chiếu
- [ ] Security checklist (`.claude/rules/security.md`) pass cho backend
- [ ] Crash-free > 99.5% trong internal testing
- [ ] Privacy policy + store listing sẵn sàng

### Post-Launch (beta metrics)

| Metric | Baseline | Target | Actual |
|--------|----------|--------|--------|
| D7 retention | — | > 20% | TBD |
| Ảnh/user/tuần | — | ≥ 10 | TBD |
| % ảnh score ≥ 80 khi theo hint | — | > 60% | TBD |
| Hint feedback positive rate | — | > 70% | TBD |

## Related Documents

- [PRD](prd/PRD-shotmate-mvp.md)
- [System Design](design/system-design-shotmate.md)
- [ADR 0001–0006](adr/)
- [Spec Sprint 1](specs/spec-sprint-1.md)

---

## Changelog

| Date | Author | Change |
|------|--------|--------|
| 2026-07-03 | Đạt Trần | Initial roadmap |
| 2026-07-03 | Đạt Trần (swarm) | Sprint 1 Dart layer done (commit `b5568dc`): rule engine, PhotoScorer, Drift, capture flow, 4 màn hình, Perf HUD scaffolding — 80/80 test. Phase 1 → In Progress; còn native module + benchmark gate. Chi tiết: [sprint-1-status.md](specs/sprint-1-status.md) |
