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
**Last Updated:** 2026-07-07 (Sprint 4 code D1–D7 + FR-S4-9 xong; iOS + deploy GCP cắt khỏi scope thực thi)
**Beads Issue:** N/A
**Timeline:** 2026-07-07 → 2026-08-15 (MVP 3 sprint × 2 tuần) + Sprint 4 hardening/beta + V1–V4 sau beta

> **Pace thực tế:** Sprint 1–3 code core đã implement xong 2026-07-07 (sớm ~4–5 tuần so với lịch danh nghĩa). Lịch các phase dưới giữ nguyên làm mốc danh nghĩa; deadline cứng duy nhất là **beta 2026-08-15**.

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
**Status:** In Progress — **code core implement sớm 2026-07-07** (commit `5c77b9d`): backend 61/61 test, app 132/132 test, cả hai quality gate xanh. Chưa deploy; nợ D1–D8 ghi trong [spec-sprint-3.md](specs/spec-sprint-3.md) §Implementation Notes → chuyển sang Phase 4.

**Deliverables:** (chi tiết + thứ tự cắt scope: [spec-sprint-3.md](specs/spec-sprint-3.md))
- [x] NestJS API: auth magic link + JWT (rotation + reuse detection), users, photos (signed URL), sync LWW, feedback, DELETE /me — code + unit test xong; **chưa deploy Cloud Run** (Phase 4)
- [x] Cloud AI review pipeline: BullMQ + `AiReviewProvider` (Claude + Gemini, failover, zod) — worker còn chạy in-process với API (D2, Phase 4)
- [x] Credits server-side atomic + refund + Subscription qua RevenueCat webhook/verify — **app-side SDK + paywall thật chưa có** (D8, Phase 4)
- [x] App wiring Android: features/auth + review (upload → enqueue → poll → Drift), secure storage, Dio interceptor refresh
- [ ] Firebase Analytics dashboard + Crashlytics triage flow → Phase 4 (D8)
- [ ] Beta: TestFlight + Play Internal track, 50 testers → Phase 4 (FR-S4-11)

**Dependencies:** Phase 2 complete; Apple/Google dev accounts + GCP project sẵn sàng **trước** sprint

**Risks:**
- Sprint dày nhất (đã biết trước — ADR-0002 đánh đổi có chủ đích) → nếu trễ, cắt sync đa thiết bị ra sau beta, giữ auth + review + subscription
- App review 2 store lâu → submit build từ giữa sprint

---

### Phase 4: Sprint 4 — Beta Hardening + Launch (Android-only)

**Timeline:** danh nghĩa 2026-08-18 → 2026-08-29; **thực tế bắt đầu ngay 2026-07-07, code core xong cùng ngày** (pace sớm) — deadline cứng: beta 2026-08-15
**Status:** In Progress — code (FR-S4-1..7, FR-S4-9) xong 2026-07-07 (swarm); còn phần cần account/thiết bị thật (FR-S4-10, FR-S4-11). Spec: [spec-sprint-4.md](specs/spec-sprint-4.md)

Không feature mới — biến code Sprint 3 thành hệ thống chạy thật (local/integration) + launch beta **Android-only**. **iOS cắt hoàn toàn khỏi phase này** (không macOS host/iPhone 12 sẵn sàng — dời sang Phase 5). **Deploy GCP thật cũng ngoài phạm vi thực thi** (không có gcloud/credentials trong môi trường thực thi) — chuẩn bị deploy-ready, chủ dự án tự chạy khi có GCP project.

**Deliverables:** (chi tiết + thứ tự cắt scope: [spec-sprint-4.md](specs/spec-sprint-4.md))
- [x] Chuẩn bị deploy-ready: Dockerfile 2-target (api/worker), CI workflow gated, `infra/DEPLOY.md` hướng dẫn deploy Cloud Run thật (FR-S4-1)
- [x] Trả nợ D1–D7: rate limit Redis-backed đầy đủ, tách worker service, storage minio thật (S3 SDK), webhook zod + route `GET /photos`, pino redact + helmet, integration test DB live — **87 unit + 13 integration test, tất cả pass trên docker compose thật** (FR-S4-2..7)
- [x] App: RevenueCat SDK + paywall thật (public key thật đã cấu hình `app/dart_defines.local.json`), resize isolate, Firebase init graceful (code xong, chờ Firebase project cho Analytics/Crashlytics thật) — **139/139 test** (FR-S4-9)
- [ ] Nợ Sprint 2: accuracy scene ≥85% (150 ảnh) + user test hint overload (FR-S4-10) — cần ảnh/người test thật, ngoài phạm vi code
- [ ] Beta launch Android-only: security audit, benchmark 50 ảnh + cost ≤$0.01 (cần API key thật), store submit Play Internal tuần 1, 50 testers (FR-S4-11)

**Dependencies:** Phase 3 code (đã có); **API key thật** (Anthropic, Gemini) cho benchmark; **RevenueCat public key đã có** (2026-07-07), còn thiếu Play Console product `monthly` cho sandbox purchase thật; Firebase project; GCP project + billing chỉ cần khi deploy thật (không chặn code sprint này)

**Risks:**
- Chưa có API key thật (Anthropic/Gemini) → benchmark/cost đo thật (FR-S4-11) chờ đến khi Đạt điền key vào `backend/.env`
- Store review chậm → submit trong tuần 1 (đã chốt trong spec)
- Accuracy scene <85% → spike TFLite timebox 3 ngày (đường thoát ADR-0006), không chặn launch

---

### Phase 5+: Post-MVP (V1 → V4)

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
| Sprint 2 done — full coaching offline | 2026-08-01 | In Progress | Logic + native Android xong sớm 2026-07-06 (pose/scene/zoom/distance/angle/countdown, 126 test); còn iOS + đo accuracy scene + user test (→ Sprint 4 FR-S4-8/10) |
| Sprint 3 done — backend + monetization code | 2026-08-15 | In Progress | Code core xong sớm 2026-07-07 (`5c77b9d`): backend 61 test, app 132 test. Còn deploy + nợ D1–D8 → Sprint 4 |
| Sprint 4 code (D1–D7, FR-S4-9) done | 2026-08-29 | In Progress | Code xong sớm 2026-07-07: backend 87 unit + 13 integration test (DB/Redis/minio/mailpit thật) pass; app 139 test. Còn FR-S4-10/11 cần account/ảnh/người test thật |
| Beta launch (Play Internal, Android-only) | 2026-08-15 | Pending | Beta gate = spec-sprint-4 Rule 2 (security audit, crash-free, benchmark, rate limit, integration test) |
| Public launch quyết định sau beta | TBD | Pending | Dựa trên D7 retention + feedback |

## Resource Allocation

| Phase | Engineering | Design | Product | QA |
|-------|-------------|--------|---------|-----|
| Phase 1 | 1 (Đạt) | 0.2 (Đạt) | 0.1 | kèm dev |
| Phase 2 | 1 | 0.3 (UX hint là trọng tâm) | 0.1 | kèm dev |
| Phase 3 | 1 | 0.1 | 0.2 (pricing/beta) | kèm dev |
| Phase 4 | 1 | 0.1 (store listing) | 0.3 (beta ops/tuyển tester) | kèm dev + integration suite |

> Solo dev — con số là tỷ trọng thời gian. Swarm workers (Claude Code) dùng để song song hoá: builder cho rule engine/backend module, reviewer cho security pass trước beta.

## Dependencies

```
Phase 1 ──────→ Phase 2 ──────→ Phase 3 ──────→ Phase 4 ──────→ V2/V3/V4
   │                               ↑                ↑
   └── Benchmark gate       Store accounts     GCP deploy + macOS host (iOS)
                            + GCP project      + RevenueCat account
```

| Dependency | Owner | Status | Risk Level |
|------------|-------|--------|------------|
| Thiết bị test tham chiếu (Pixel 6a, iPhone 12) | Đạt | Android có (Xiaomi thay Pixel); iPhone 12 chưa — chặn gate iOS (EC-S4-8) | M |
| Apple Developer + Play Console accounts | Đạt | Cần trước Phase 4 tuần 1 (store submit) | M |
| GCP project + billing | Đạt | Cần trước Phase 4 (FR-S4-1 deploy) | L |
| Claude + Gemini API keys | Đạt | Cần trước Phase 4 (worker chạy thật) | L |
| macOS host cho iOS build | Đạt | Chưa chốt — không có = cắt iOS khỏi beta (spec-sprint-4 Rule 3) | H |
| RevenueCat account + webhook secret | Đạt | Cần trước FR-S4-9 | L |

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

- [ ] Toàn bộ acceptance criteria spec Sprint 1–4 pass (beta gate chi tiết: spec-sprint-4 Rule 2)
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
- [ADR 0001–0007](adr/)
- [Spec Sprint 1](specs/spec-sprint-1.md) · [Spec Sprint 2](specs/spec-sprint-2.md) · [Spec Sprint 3](specs/spec-sprint-3.md) · [Spec Sprint 4](specs/spec-sprint-4.md)

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
| 2026-07-06 | Đạt Trần (swarm) | **Spec Sprint 3**: [spec-sprint-3.md](specs/spec-sprint-3.md) — auth magic link/JWT, upload signed URL, review pipeline BullMQ + adapter, credits server-side atomic + refund, subscription (RevenueCat — assumption chờ chốt), sync LWW, account deletion (App Store 5.1.1(v)), iOS native module (nợ Sprint 2), thứ tự cắt scope cố định (sync → iOS → feedback). |
| 2026-07-07 | Đạt Trần (swarm) | **Sprint 3 code core implement sớm** (commit `5c77b9d`): backend NestJS đầy đủ modules (auth/photos/analysis+worker/credits/subscriptions/sync/users/feedback/health) 61/61 test + lint 0; app Android wiring (features/auth + review, secure storage, Dio refresh interceptor) 132/132 test, analyze 0. Adversarial review + fixes áp (CWE-639 sync, EC-S3-3, refund atomic, ValidationPipe 422). Deviations D1–D8 ghi trong spec §Implementation Notes. Phase 3 → In Progress. |
| 2026-07-07 | Đạt Trần (swarm) | **Thêm Phase 4 — Sprint 4 Beta Hardening + Deploy + Launch** + [spec-sprint-4.md](specs/spec-sprint-4.md): trả nợ D1–D8 (rate limit Redis, tách worker service, GCS/minio thật, webhook zod + `GET /photos`, pino/helmet/OTel, integration test DB live), iOS native module (gate iPhone 12), RevenueCat SDK + Firebase app-side, nợ Sprint 2 (accuracy scene 150 ảnh + user test hint), beta launch 50 testers. Post-MVP đổi thành Phase 5+. Verify local 2026-07-07: backend 61/61, app 132/132 (sau `npm install` + `build_runner` — 2 gate xanh). |
| 2026-07-07 | Đạt Trần (swarm) | **Cắt iOS + deploy GCP thật khỏi Sprint 4** (quyết định, không phải "cắt nếu trễ"): không có macOS host/iPhone 12/gcloud credentials trong môi trường thực thi. FR-S4-1 đổi thành chuẩn bị deploy-ready; FR-S4-8 dời sang Phase 5. |
| 2026-07-07 | Đạt Trần (swarm) | **Sprint 4 D1–D7 + FR-S4-9 implement xong** (4 worker song song cho D1/D4/D5/D6 + orchestrator cho D2/D3/D7/FR-S4-1/app): backend **87 unit + 13 integration test pass thật** trên docker compose (postgres/redis/minio/mailpit) — auth e2e đầy đủ (magic-link→mailpit→verify→refresh rotation→reuse revoke), credit race EC-S3-1, refund EC-S3-2, sync conflict LWW EC-S3-6, DELETE /me EC-S3-11; lint 0 · build 0 lỗi. App: RevenueCat SDK + PaywallScreen + resize isolate + Firebase init graceful — **139/139 test**, analyze 0. **Bug hạ tầng test phát hiện + fix**: Vitest/esbuild không emit decorator metadata cho NestJS DI (tồn tại tiềm ẩn từ Sprint 3, lộ ra khi bootstrap `AppModule` thật lần đầu) — fix bằng `unplugin-swc` (giải pháp chính thức NestJS cho Vitest). RevenueCat Public SDK key thật đã cấu hình (`app/dart_defines.local.json`, gitignored). Còn nợ trước beta gate: deploy GCP thật, sandbox purchase (chờ Play Console product), Firebase project thật, benchmark 50 ảnh (chờ API key thật), accuracy scene + user test (FR-S4-10). |
