# ADR-0006: On-device ML stack — MediaPipe (pose) + ML Kit (face/object/labeling) + TFLite (custom)

## Metadata

**Status:** Accepted · **Date:** 2026-07-03 · **Deciders:** Đạt Trần · **Tags:** ai, mobile, ml
**Related PRD:** [PRD-shotmate-mvp.md](../prd/PRD-shotmate-mvp.md) · **Supersedes:** N/A · **Superseded By:** N/A

**Tech Strategy:** ✅ Follows Golden Path

---

## Context

Native inference module (ADR-0001) cần các detector: pose/skeleton (33 landmarks cho Pose Guide), face (chin/smile hints), subject/object detection (composition + distance), scene classification (landscape/portrait/food cho Zoom Suggestion), và về sau có thể custom model (aesthetic scoring). Tất cả phải chạy realtime on-device, free, hỗ trợ cả Android + iOS.

---

## Decision Drivers

- Realtime trên máy tầm trung: pose ≤ 30ms/frame, có GPU delegate
- Cross-platform: cùng model/behavior trên Android + iOS
- Miễn phí, không giới hạn call (chạy 15fps liên tục)
- Model bundle size hợp lý (app < 150MB, NFR-5)
- Đường mở cho custom model khi cần (V2+ scene, aesthetic model)

---

## Considered Options

### Option 1: Google ML Kit toàn bộ

| Pros | Cons |
|------|------|
| API cao cấp, dễ tích hợp, free | Pose của ML Kit ít cấu hình hơn MediaPipe |
| Face/object/labeling rất trưởng thành | Không chạy custom model tuỳ ý (trừ custom classification) |

### Option 2: MediaPipe Tasks toàn bộ

| Pros | Cons |
|------|------|
| Pose Landmarker mạnh nhất (33 points, 3 độ nặng model, GPU delegate) | Face/object/labeling phải tự cấu hình nhiều hơn ML Kit |
| Chạy model .task tuỳ biến | |

### Option 3: Mix theo thế mạnh — MediaPipe pose + ML Kit face/object/labeling + TFLite custom

| Pros | Cons |
|------|------|
| Mỗi detector dùng SDK tốt nhất cho việc đó | 2 SDK cùng lúc trong native module — quản lý version |
| TFLite runtime là đường thoát cho mọi custom model sau này | |
| Cả 3 đều free, cùng nhà Google, chung TFLite runtime bên dưới | |

---

## Decision Outcome

**Chosen Option:** Option 3 — MediaPipe Pose Landmarker (lite model) + ML Kit (face detection, object detection & tracking, image labeling) + TFLite runtime cho custom model tương lai

**Rationale:** Pose là detector nặng và quan trọng nhất → dùng MediaPipe (model `pose_landmarker_lite`, GPU delegate, ~30ms trên máy tầm trung). Face/object/labeling là commodity → ML Kit nhanh gọn nhất. Cả hai chung gia đình Google, chạy trên TFLite — không xung đột runtime. Scene classifier V1 dùng ML Kit image labeling map label→scene; nếu độ chính xác không đủ, train TFLite classifier nhỏ (đường thoát đã có sẵn).

Horizon detection KHÔNG cần ML: dùng gyroscope/CoreMotion cho device tilt + edge detection nhẹ cho đường chân trời thực.

### Quantified Impact

| Detector | SDK | Model size | Latency target (máy tầm trung) |
|----------|-----|-----------|-------------------------------|
| Pose | MediaPipe pose_landmarker_lite | ~5MB | ≤ 30ms GPU |
| Face | ML Kit face detection | ~1MB (bundled) | ≤ 15ms |
| Object/subject | ML Kit ODT | ~5MB | ≤ 20ms @5fps |
| Scene labeling | ML Kit image labeling | ~5MB | ≤ 30ms @1fps |
| **Tổng bundle thêm** | | **~16MB** | Trong NFR-5 |

---

## Consequences

**Positive:**
- Không chi phí API, không mạng, privacy nguyên vẹn; behavior đồng nhất 2 nền tảng
- Detector Scheduler (ADR-0001) điều phối tần suất từng SDK độc lập

**Negative:**
- Native module phụ thuộc 2 SDK — theo dõi release notes cả hai
- ML Kit là closed-source — nếu Google khai tử 1 API phải thay bằng MediaPipe tương đương (rủi ro thấp, đường thay có sẵn)

**Risks:**
- Scene classification bằng generic labeling không đủ chính xác cho food vs portrait → fallback: train TFLite classifier 3 lớp bằng dataset công khai (spike Sprint 2)

---

## Validation

- [ ] Benchmark Sprint 1: pose 15fps + composition 5fps đồng thời, đo latency + nhiệt trên Pixel 6a / iPhone 12
- [ ] Scene classifier accuracy ≥ 85% trên validation set 300 ảnh (Sprint 2)
- [x] Tech Strategy alignment confirmed

---

## Links

- [ADR-0001 Native processing](./0001-native-side-frame-processing.md) · [System Design §3](../design/system-design-shotmate.md)

---

## Changelog

| Date | Author | Change |
|------|--------|--------|
| 2026-07-03 | Đạt Trần | Initial draft |
