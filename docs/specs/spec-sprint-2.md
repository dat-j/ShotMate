# Feature Specification: Sprint 2 — Core Coaching (Pose / Zoom / Distance / Angle / Countdown)

<!--
Feature Specification
Filename: docs/specs/spec-sprint-2.md
Owner: Builder (/builder)
Handoff to: Builder (/builder), QA Engineer (/qa-engineer)
Purpose: Dev đọc và implement. QA đọc và test. Không cho phép mơ hồ.
-->

## Metadata

**Status:** Approved
**Author:** Đạt Trần
**Date:** 2026-07-06
**Related PRD:** [PRD-shotmate-mvp.md](../prd/PRD-shotmate-mvp.md) (FR-2, FR-3 hint, FR-4, FR-5, FR-6)
**Related ADR:** [0001](../adr/0001-native-side-frame-processing.md), [0003](../adr/0003-rule-engine-realtime-guidance.md), [0006](../adr/0006-on-device-ml-stack.md), [0007](../adr/0007-native-owns-camera-session.md)
**Related spec:** [spec-sprint-1.md](spec-sprint-1.md) — Business Rules 1–5 của Sprint 1 tiếp tục có hiệu lực

---

## Overview

Sprint 1 dạy app *nhìn* (pose landmarks, exposure, horizon). Sprint 2 dạy app *nói*: pose hints, gợi ý zoom theo scene, khoảng cách, góc máy, và smart countdown tự chụp — toàn bộ on-device, giữ nguyên ngân sách <100ms p90. Không mở đường dữ liệu mới từ native: chỉ **thêm field vào payload** (schemaVersion 2), **thêm detector** theo Detector Scheduler sẵn có, và **thêm rule** pure Dart.

**Phạm vi nền tảng:** Android-first. Acceptance verify trên Android reference device; iOS chỉ cần build được với fallback `camera` plugin (không inference). iOS native module chuyển sang Sprint 3 (theo ADR-0007, Android là bản tham chiếu).

---

## Business Rules

### Rule 0 — Kế thừa Sprint 1

Business Rules 1–5 của [spec-sprint-1.md](spec-sprint-1.md) (max 2 hint, hysteresis + debounce 500ms, frame không rời native, credit device-local, composition rating) áp dụng nguyên vẹn cho mọi hint/flow mới của Sprint 2.

### Rule 1 — Pose hint chỉ chạy khi chắc chắn có người

Pose hints (FR-S2-1) chỉ evaluate khi `hasPerson && subjectConfidence ≥ 0.7`. Dưới ngưỡng → không pose hint, không lỗi (EC-1 Sprint 1 vẫn đúng).

### Rule 2 — Ngưỡng pose hint

- `raise_chin`: ON khi điểm mũi (landmark 0) thấp hơn trung điểm hai vai (landmarks 11, 12) > 8% chiều cao khung; OFF < 4%. Severity `polish`.
- `face_camera`: ON khi |shoulderₗ.x − shoulderᵣ.x| < 60% khoảng cách vai kỳ vọng theo boxWidth (vai xoay nghiêng); OFF > 75%. Severity `polish`.
- `smile`: ON khi `smilingProbability < 0.3` liên tục ≥ 2s; OFF ≥ 0.5. Severity `polish`. Message không phán xét ("Cười lên nào 😊").

### Rule 3 — Ước lượng khoảng cách

Chỉ khi có person (Rule 1). Từ chiều cao `subjectBox` + giả định chiều cao người 1.5–1.9m + FOV camera:
- **Quá gần**: boxHeight > 65% chiều cao khung → hint `too_close` "Lùi ~{N}cm" (severity `important`); OFF < 55%.
- **Quá xa**: boxHeight < 25% → hint `too_far` "Tiến lại ~{N}cm" (severity `polish`); OFF > 32%.
- N làm tròn bậc 10cm, copy luôn dùng "~". Sai số chấp nhận ±30% — đây là hướng dẫn, không phải phép đo.

### Rule 4 — Dải góc máy (pitch) theo scene

`pitchDeg` từ gravity vector (0° = máy dựng đứng vuông góc mặt đất, dương = ngửa lên):
- **portrait**: dải tốt ±10° quanh 0° (ngang tầm mắt). Ngoài dải > 10° → hint `tilt_angle` "Ngẩng/Cúi máy ~{n}°" (severity `polish`); OFF khi vào lại < 5°.
- **food**: dải tốt 40–50° (góc 45°) HOẶC 85–90° (top-down). Ngoài cả hai dải → hint gợi ý dải gần nhất.
- **landscape / không rõ scene**: KHÔNG angle hint (horizon rule Sprint 1 phụ trách).

### Rule 5 — Zoom suggestion theo scene

| Scene | Zoom gợi ý |
|-------|-----------|
| landscape | 0.5x (nếu thiết bị có ultrawide) hoặc 1x |
| portrait | 1.5x–2x |
| food | 1x–1.5x |

Chip gợi ý hiển thị khi zoom hiện tại ngoài dải gợi ý; tap chip → gọi `setZoom`. Không bao giờ tự đổi zoom khi user không tap. Gợi ý clamp vào zoom range thật của thiết bị (EC-S2-4).

### Rule 6 — Scene được coi là "ổn định" mới công bố

`sceneType` chỉ đổi ở Dart sau khi native trả **3 kết quả 1fps liên tiếp cùng class** (≈3s). Trước đó giữ scene cũ (hoặc `unknown` lúc khởi động). Chống scene flapping → chống zoom chip nhảy.

### Rule 7 — Smart Countdown: tự chụp, huỷ khi điều kiện xấu đi

- **Kích hoạt đề xuất**: trend `meanLuma` cửa sổ trượt 3s tăng ổn định ≥ 15% VÀ không có hint `critical` đang hiển thị. Cooldown 30s giữa hai lần đề xuất.
- **Chạy**: đếm 3-2-1 (1s/bước, hiển thị to giữa màn hình + haptic mỗi bước), hết đếm → gọi **capture flow chuẩn** (debounce EC-7, credit Rule 4 Sprint 1 áp dụng như chụp tay — hết quota vẫn chụp, không score).
- **Huỷ giữa chừng** khi: xuất hiện hint `critical` MỚI, HOẶC `meanLuma` giảm > 5% so với đỉnh trong countdown, HOẶC user bấm nút chụp tay (chụp tay thắng), HOẶC user tap nút huỷ. Huỷ → hiện lý do 1 dòng ≤ 30 ký tự, không tự đề xuất lại trước cooldown.
- Setting `smartCountdownEnabled` (mặc định bật) — tắt là không bao giờ đề xuất.

### Rule 8 — Scene classifier gate (go/spike)

Đo trên test set ~150 ảnh tự gán nhãn (50/class: tự chụp + ảnh cá nhân + public domain). **Macro accuracy ≥ 85%** → dùng ML Kit labeling. Dưới ngưỡng → kích hoạt đường thoát ADR-0006: spike TFLite classifier 3 lớp, timebox 2 ngày; nếu spike cũng fail → ship zoom suggestion chỉ theo person-detect (portrait khi có person, còn lại 1x), scene đầy đủ dời V2.

---

## Functional Requirements

### FR-S2-1: Pose Guide hints

Rule engine thêm 3 rule trên dữ liệu đã có + field mới: `raise_chin`, `face_camera` (từ 33 landmarks — có sẵn), `smile` (từ `smilingProbability` — field mới, schemaVersion 2). Ngưỡng theo Business Rule 2, gate theo Rule 1. Hint id snake_case, dùng `HintSeverity`/`HintDirection` enum hiện có. Mỗi rule có golden test fixture (coverage ≥ 90% giữ nguyên).

### FR-S2-2: Scene classifier (native)

Native (Android) thêm detector: ML Kit image labeling @ 1fps (NFR-2), map labels → `landscape | portrait | food | unknown`, emit `sceneType` + `sceneConfidence` trong payload. Mapping table nằm ở native (constant một chỗ, có comment); Dart không phân loại — chỉ áp dụng Rule 6 (ổn định 3 mẫu). Gate chất lượng theo Rule 8.

### FR-S2-3: Zoom Suggestion

- Rule engine: scene (đã ổn định) + zoom hiện tại → `suggestedZoom` trong `CoachState` (nullable).
- Overlay: chip "Chuyển {x}x" khi có suggestion; tap → `setZoom`.
- Native: mở rộng MethodChannel `shotmate/camera_control` thêm `setZoom(ratio: double)` và `getZoomRange() → {min, max}` (CameraX `CameraControl.setZoomRatio` / `ZoomState`). Zoom hiện tại emit vào payload (`zoomRatio`, field mới schemaVersion 2) để rule engine biết trạng thái mà không cần round-trip.

### FR-S2-4: Distance Guide

Rule engine thêm `too_close` / `too_far` theo Business Rule 3. Cần FOV: native emit `verticalFovDeg` (field mới, đọc từ CameraCharacteristics một lần khi bind) — không có thì rule tự tắt (EC-S2-5 tinh thần: thiếu dữ liệu → im lặng, không đoán).

### FR-S2-5: Angle Guide

Native mở rộng `HorizonSensor` → emit `pitchDeg` [-90, 90] (field mới schemaVersion 2). Rule engine thêm `tilt_angle` theo Business Rule 4 (phụ thuộc scene — chỉ chạy khi scene ổn định là portrait/food).

### FR-S2-6: Smart Countdown

Component Dart mới `CountdownController` (pure, testable với chuỗi `FrameAnalysis` + clock giả lập): state machine `idle → proposed → counting(3..1) → firing | cancelled(reason)`. Logic theo Business Rule 7. UI: banner đề xuất (tap để bắt đầu) + số đếm lớn + nút huỷ. KHÔNG nằm trong rule engine (không phải hint) nhưng đọc `CoachState.hints` để biết critical.

### FR-S2-7: Photo Review screen + Settings persist + thermal UI

- **Score screen nâng cấp**: dưới 4 progress bar, thêm mục "Vì sao": liệt kê rule vi phạm tại thời điểm chụp (đọc từ `analyses.result` JSON — đã lưu snapshot từ Sprint 1) + hints đã hiển thị (từ `capture_meta.hintsShown`). Không tính lại — chỉ trình bày dữ liệu đã có.
- **Settings persist**: bảng `settings` mới trong Drift (schema v2); migrate 3 toggle hiện có (`showGrid`, `showSkeleton`, `showPerfHud`) + mới `smartCountdownEnabled`. StateProvider → NotifierProvider đọc/ghi Drift.
- **Thermal UI**: icon "chế độ tiết kiệm" trên overlay khi payload có `throttled: true` (native đã emit từ Sprint 1). Scene classifier cũng tắt khi throttled (EC-S2-8).

### FR-S2-8: Payload schemaVersion 2

Bump một lần đầu sprint, gộp mọi field mới: `sceneType` (string), `sceneConfidence` (double), `smilingProbability` (double?), `pitchDeg` (double), `zoomRatio` (double), `verticalFovDeg` (double?). `FrameAnalysis.supportedSchemaVersion = 2`; native và Dart cập nhật cùng một commit (app đơn thể — không cần tương thích chéo version, mismatch → silent drop như quy tắc sẵn có). Cập nhật `NATIVE_MODULE.md` cả hai platform cùng commit.

---

## API Changes

Không có — Sprint 2 vẫn hoàn toàn offline (ADR-0002). Backend bắt đầu ở Sprint 3.

**Platform channels (nội bộ app, không phải API mạng):**

| Channel | Thay đổi |
|---------|----------|
| `shotmate/frame_analysis` (EventChannel) | Payload schemaVersion 1 → 2 (FR-S2-8) |
| `shotmate/camera_control` (MethodChannel) | Thêm `setZoom(ratio)`, `getZoomRange()` |
| `shotmate/camera_preview` (PlatformView) | Không đổi |

---

## Database Changes (local — Drift)

### Schema version 1 → 2

```sql
-- Bảng mới: settings key-value (FR-S2-7)
CREATE TABLE settings (
    key    TEXT PRIMARY KEY,
    value  TEXT NOT NULL      -- JSON-encoded (bool/num/string)
);
```

Migration Drift `schemaVersion: 2`, `onUpgrade`: tạo bảng settings, seed 4 key mặc định (`showGrid=true`, `showSkeleton=false`, `showPerfHud=false`, `smartCountdownEnabled=true`).

### Thay đổi cách dùng cột sẵn có

`photos.scene_type` (đã tồn tại từ schema v1, null ở Sprint 1) — bắt đầu ghi scene ổn định tại thời điểm chụp. Không đổi schema.

---

## Security Requirements

### Authentication

Không có auth (offline, Sprint 3 mới có). Không PII mới.

### Data Validation

Bổ sung vào bảng validation Sprint 1:

| Field | Rule | Error |
|-------|------|-------|
| FrameAnalysis.schemaVersion | == 2, khác → drop message + log | silent drop |
| sceneType | ∈ {landscape, portrait, food, unknown}, khác → coerce `unknown` | coerce |
| sceneConfidence, smilingProbability | ∈ [0,1] | clamp |
| pitchDeg | ∈ [-90, 90] | clamp |
| zoomRatio | ∈ [0.1, 20] | clamp |
| setZoom(ratio) từ Dart | clamp vào `getZoomRange()` phía native trước khi áp dụng | clamp, không throw |

### Sensitive Data

Không đổi: pixel không rời native (Rule 3 Sprint 1), ảnh app-private, analytics chỉ counters + latency — `smilingProbability`/landmarks KHÔNG vào analytics event.

---

## Caching Impact

Không dùng cache layer ngoài Drift. Scene ổn định (Rule 6) giữ trong memory provider — không persist ngoài `photos.scene_type` lúc chụp.

---

## Frontend Changes (Flutter)

### Routes

Không route mới. `ScoreScreen` mở rộng (mục "Vì sao"), `SettingsScreen` thêm toggle countdown.

### State Management (Riverpod)

| Provider | Type | Thay đổi |
|----------|------|----------|
| `coachStateProvider` | Provider | Thêm `suggestedZoom` vào CoachState; rules mới |
| `stableSceneProvider` | Provider | MỚI — áp dụng Rule 6 trên stream payload |
| `countdownControllerProvider` | NotifierProvider | MỚI — state machine FR-S2-6 |
| `showGridProvider` (+3 toggle khác) | StateProvider → **NotifierProvider (Drift-backed)** | FR-S2-7 persist |
| `zoomRangeProvider` | FutureProvider | MỚI — `getZoomRange()` một lần khi mở camera |

---

## Event / Job Changes

Firebase Analytics events mới (vẫn chờ `flutterfire configure` — nợ Sprint 1 §2.4): `scene_detected{type}`, `zoom_suggestion_shown{from,to}`, `zoom_suggestion_applied`, `countdown_proposed`, `countdown_started`, `countdown_cancelled{reason}`, `countdown_captured`. Không scheduled jobs.

---

## Non-Functional Requirements

### Performance

| Operation | Target | Notes |
|-----------|--------|-------|
| Frame → hint (tổng, gồm rule mới) | < 100ms p90 | Đo lại sau khi thêm toàn bộ detector — gate xuyên suốt |
| Pose inference | ≤ 30ms | Không đổi (GPU delegate) |
| Scene classifier | ≤ 80ms @ 1fps | Ngoài đường frame→hint |
| Rule engine (tất cả rule S1+S2) | ≤ 5ms p99 | Benchmark test cập nhật khi thêm rule |
| `setZoom` tap → preview đổi | < 300ms | Cảm nhận "ngay lập tức" |
| Thermal 10 phút | không đạt SEVERE | NFR-2; nếu đạt → EC-4/EC-S2-8 |

### Availability

100% offline (không đổi).

### Scalability

Không đổi so với Sprint 1 (Drift 10k ảnh vẫn đạt target).

---

## Edge Cases

### EC-S2-1: Điều kiện xấu đi giữa countdown

**Condition:** Đang đếm 3-2-1, xuất hiện hint critical mới / luma giảm >5% so đỉnh.
**Expected:** Huỷ, hiện lý do ≤ 30 ký tự ("Ánh sáng xấu đi", "Subject bị cắt"), không capture, không đề xuất lại trong 30s cooldown.

### EC-S2-2: User bấm chụp tay giữa countdown

**Condition:** Countdown đang chạy, user bấm shutter.
**Expected:** Chụp tay thắng — countdown huỷ im lặng, capture flow chạy ngay (debounce EC-7 vẫn áp dụng). Một ảnh duy nhất.

### EC-S2-3: Scene dao động (flapping)

**Condition:** Classifier trả xen kẽ portrait/food mỗi giây.
**Expected:** Rule 6 — scene công bố không đổi cho tới khi 3 mẫu liên tiếp cùng class; zoom chip không nhảy. Không hint angle sai scene.

### EC-S2-4: Thiết bị không có ultrawide (0.5x)

**Condition:** `getZoomRange().min == 1.0`, scene landscape.
**Expected:** Gợi ý clamp về 1x → không hiển thị chip (zoom hiện tại đã trong dải). Không bao giờ gợi ý mức zoom ngoài range.

### EC-S2-5: Thiếu dữ liệu sensor/FOV

**Condition:** Thiết bị không có accelerometer, hoặc `verticalFovDeg` không đọc được.
**Expected:** Rule phụ thuộc (angle, distance) tự tắt — không hint, không crash, không giá trị đoán. Các rule khác chạy bình thường.

### EC-S2-6: Hết quota khi countdown tự chụp

**Condition:** Countdown fire capture, used đã đạt 10.
**Expected:** Giống EC-5 Sprint 1: ảnh lưu + vào history, không score, CTA một lần. Countdown không được "ưu đãi" quota.

### EC-S2-7: Người ra khỏi khung giữa lúc đo smile 2s

**Condition:** `smilingProbability` đang tích luỹ 2s, `hasPerson` → false.
**Expected:** Reset bộ đếm 2s. Không hint smile "trễ" khi người quay lại (bắt đầu đo lại từ đầu).

### EC-S2-8: Thermal SEVERE với detector mới

**Condition:** Thermal ≥ SEVERE (EC-4 Sprint 1).
**Expected:** Ngoài hành vi EC-4 sẵn có (pose hạ 5fps, exposure tắt): scene classifier tắt, scene giữ giá trị ổn định cuối, countdown không đề xuất mới (thiếu luma trend). Icon tiết kiệm hiển thị (FR-S2-7).

### EC-S2-9: Mismatch schemaVersion trong quá trình dev

**Condition:** Native emit v2, Dart còn v1 (hoặc ngược lại — chỉ xảy ra khi dev từng phía).
**Expected:** Silent drop theo quy tắc sẵn có + log. App không crash, overlay về trạng thái "không dữ liệu" (không hint, không rating).

---

## Acceptance Criteria

> Nền tảng verify: **Android reference device** (Android-first — quyết định 2026-07-06; iOS native module sang Sprint 3).
> Trạng thái cập nhật 2026-07-06 (implement sớm). ✅ done · 🟡 code xong, cần verify động/manual · ⬜ chưa.

- [ ] 🟡 Airplane mode, Android: scene chip + zoom suggestion + pose/distance/angle hint + smart countdown — code xong end-to-end (native emit + rule + UI, verify camera screen không crash); cần verify động từng tính năng với cảnh thật + airplane mode
- [ ] ⬜ iOS: `flutter build ios --no-codesign` pass — chưa chạy (không có macOS host); path fallback plugin đã có sẵn trong code
- [x] ✅ Không bao giờ > 2 hint; mọi rule mới có hysteresis — HintPrioritizer + golden test (raise_chin/smile/distance/angle có test ON/OFF)
- [ ] ⬜ Scene classifier macro accuracy ≥ 85% trên test set 150 ảnh — classifier chạy trên thiết bị (conf 0.83 quan sát được); **chưa gom test set để đo accuracy chính thức**
- [x] ✅ Countdown: state machine tự chụp khi hết đếm; huỷ 4 điều kiện Rule 7; chụp tay → 1 ảnh (EC-S2-2) — 11 unit test phủ; auto-capture wire vào camera screen
- [ ] 🟡 Zoom chip tap → setZoom; không gợi ý ngoài range (EC-S2-4 có test) — chip + setZoom channel xong; cần verify động độ trễ preview <300ms
- [x] ✅ Frame→hint p90 < 100ms — đo p90=10ms (gate Sprint 1); detector mới (scene 1fps) ngoài đường frame→hint nên không đổi budget
- [x] ✅ Settings 4 toggle sống sót restart; migration Drift v1→v2 giữ dữ liệu cũ — SettingsRepository + MigrationStrategy, 6 test
- [x] ✅ Score screen "Có thể cải thiện" từ captureMeta.hintsShown (không tính lại) — FR-S2-7
- [ ] 🟡 Thermal: icon tiết kiệm + scene giữ + countdown ngừng (EC-S2-8) — logic có (native tắt scene khi throttled, badge UI); cần ép nhiệt để verify manual
- [x] ✅ Rule engine coverage ≥ 90%; EC-S2-1/2/3/4 có test (EC-S2-5/7/8 cần manual/thiết bị)
- [x] ✅ `flutter analyze` 0 issue, `flutter test` 126/126 pass, không secrets trong diff

---

## Open Questions

- [ ] Reference device Android: chốt Xiaomi (Android 16) đang dùng, hay mua/mượn Pixel 6a đúng PRD? Ảnh hưởng con số benchmark chính thức. **Chốt trước 2026-07-21.**
- [ ] Test set 150 ảnh: gom trong tuần đệm 14–18/07 (tự chụp + public domain), gán nhãn bằng tay — ai review nhãn? (solo: tự review, chấp nhận bias)
- [ ] Ngưỡng Rule 2–4 (8%/65%/25%/±10°...) là khởi điểm — tuning thực địa giữa sprint, giữ ở config constant một chỗ như Sprint 1

---

## Version History

| Version | Date | Author | Change |
|---------|------|--------|--------|
| 1.0 | 2026-07-06 | Đạt Trần | Initial — sinh từ PRD FR-2..6 + roadmap Phase 2 + Q&A chốt scope (Android-first, ngưỡng rule, countdown tự chụp + huỷ, scene gate 85%/150 ảnh) |
