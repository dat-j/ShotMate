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
| Chứng minh realtime coaching khả thi | Frame→hint <100ms p90 trên Pixel 6a/iPhone 12 | ✅ Đạt (Android): p90=10ms trên Xiaomi Android 16 (2026-07-06); còn xác nhận iPhone |
| Beta với user thật | ≥ 50 beta testers, D7 retention > 20% | Not Started |
| Nền tảng doanh thu | Subscription live trên 2 store, conversion ≥ 2% | Not Started |

## Phases

### Phase 1: Sprint 1 — Foundation (Camera + Composition + Score)

**Timeline:** 2026-07-07 → 2026-07-18
**Status:** In Progress — Dart layer (`b5568dc`) + native runner (`d839b03`) + **native inference module Android** (2026-07-06, verify trên thiết bị thật) xong; còn iOS native module + nối perf + benchmark gate

**Deliverables:** (chi tiết: [spec-sprint-1.md](specs/spec-sprint-1.md), tiến độ: [sprint-1-status.md](specs/sprint-1-status.md))
- [x] Camera preview + overlay framework (grid, hints, rating) — chạy trên native preview (Android, ADR-0007) trên thiết bị thật
- [x] Native inference module **Android**: CameraX + MediaPipe pose (GPU) + ML Kit face + exposure sampler + horizon + thermal/rotation → EventChannel. Verify trên Android 16. **iOS chưa bắt đầu** (Android là tham chiếu). Xem ADR-0007 (native sở hữu camera).
- [x] Rule engine v0 (horizon, thirds, subject size/cut) + HintPrioritizer — 13 golden test
- [x] Photo Score cơ bản 4 chiều (offline) + History (Drift) + Credit tracker — focus/background dùng placeholder chờ native detector
- [x] Perf HUD + **benchmark gate <100ms (go/no-go)** — ✅ **PASS**: inferenceLatencyMs nối vào PerfTracker qua EventChannel; đo trên Xiaomi Android 16 → frame→hint p90=10ms (gấp ~10× dưới ngưỡng). Go.

**Dependencies:** None

**Risks:**
- Benchmark fail trên máy tầm trung → hạ resolution phân tích/model lite hơn; nếu vẫn fail → xét lại kiến trúc (dừng lại thay vì ship trải nghiệm lag)

---

### Phase 2: Sprint 2 — Core Coaching (Pose/Zoom/Distance/Angle/Countdown)

**Timeline:** 2026-07-21 → 2026-08-01
**Status:** In Progress — implement sớm 2026-07-06 (Android). Spec: [spec-sprint-2.md](specs/spec-sprint-2.md).

**Deliverables:**
- [x] Pose Guide hints (raise chin, smile — rule engine + golden test; native emit smilingProbability)
- [x] Scene classifier (landscape/portrait/food, ML Kit labeling 1fps) → Zoom Suggestion (chip tap→setZoom, clamp range)
- [x] Distance Guide (quá gần/xa + cm ước lượng từ FOV) + Angle Guide (tilt theo scene, pitch từ gravity)
- [x] Smart Countdown theo lighting trend (state machine + auto-capture, EC-S2-1/2)
- [x] Photo Review screen "vì sao" + Settings persist (Drift schema v2)
- [x] Thermal badge UI (throttled từ native, EC-4)

> Còn nợ Sprint 2: iOS native module (Android-first, sang Sprint 3); đo accuracy scene ≥85% trên test set 150 ảnh (chưa gom); user test hint overload; verify động zoom chip/countdown trên thiết bị (logic đã test đơn vị). Toàn bộ logic Dart + native Android xong, `flutter test` 126/126.

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
| Benchmark gate pass (<100ms) | 2026-07-11 | ✅ **Passed** 2026-07-06 | frame→hint **p90=10ms** (p50=3ms), pose p90≈40ms — đo trên Xiaomi Android 16 qua Perf HUD. Gấp ~10× dưới ngưỡng. Go. |
| Sprint 1 done — app coach được composition | 2026-07-18 | In Progress | Dart layer + runner + native inference **Android** + benchmark gate PASS xong 2026-07-06 (thiết bị thật); còn iOS module + việc nhỏ §2.4 |
| Sprint 2 done — full coaching offline | 2026-08-01 | In Progress | Logic + native Android xong sớm 2026-07-06 (pose/scene/zoom/distance/angle/countdown, 126 test); còn iOS + đo accuracy scene + user test |
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
| 2026-07-06 | Đạt Trần (swarm) | Scaffold native runner + camera permissions (commit `d839b03`, local — chưa push): `flutter create` android/ios, CAMERA/minSdk 24 (Android), NSCameraUsageDescription (iOS). Debug APK build + cài + chạy trên thiết bị thật (Android 16) không crash, camera plugin init OK. Mở khoá bước native inference module. |
| 2026-07-06 | Đạt Trần (swarm) | **Native inference module Android** (local — chưa push): CameraX (Preview+Analysis+Capture một owner) + MediaPipe pose GPU + ML Kit face + exposure sampler + horizon + thermal/rotation → EventChannel; Dart PlatformView preview + capture channel; **ADR-0007** (native sở hữu camera, giải xung đột với `camera` plugin). Verify thiết bị thật: preview + overlay chạy trên payload native, chụp OK, no crash. analyze 0 · test 80/80. iOS module còn nợ. |
| 2026-07-06 | Đạt Trần (swarm) | **Benchmark gate PASS** (local — chưa push): nối `inferenceLatencyMs` từ payload native → PerfTracker qua `frameAnalysisStreamProvider`; PerfHud tự refresh + tô đỏ khi p90≥100ms. Đo trên Xiaomi Android 16: **frame→hint p90=10ms, p50=3ms**, pose p90≈40ms — gate <100ms PASS. Thêm 4 test (84/84). Sprint 2 spec: [spec-sprint-2.md](specs/spec-sprint-2.md). |
| 2026-07-06 | Đạt Trần (swarm) | **Sprint 2 implement sớm (Android)** — 6 commit: schema v2, rule engine (pose/distance/angle), scene stability + zoom advisor + countdown state machine, Drift settings persist, native (ML Kit scene classifier + smile + pitch + zoom/FOV, verify thiết bị: scene=landscape conf=0.83, pitch=-87°, fov=64.5), UI (zoom chip/countdown/thermal/score "vì sao"). analyze 0 · test 126/126. Còn iOS + accuracy scene + user test. |
