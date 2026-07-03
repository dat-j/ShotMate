# ADR-0001: Xử lý frame camera ở native side, chỉ gửi kết quả về Dart

## Metadata

**Status:** Accepted · **Date:** 2026-07-03 · **Deciders:** Đạt Trần · **Tags:** mobile, performance, camera, ml
**Related PRD:** [PRD-shotmate-mvp.md](../prd/PRD-shotmate-mvp.md) · **Supersedes:** N/A · **Superseded By:** N/A

**Tech Strategy:** ✅ Follows Golden Path

---

## Context

Value proposition cốt lõi của ShotMate là guidance realtime **< 100ms** từ frame camera đến hint trên overlay (NFR-1). Pipeline phải chạy pose detection (~30ms), composition analysis (~15ms), scene classification, exposure sampling — liên tục khi camera mở.

Flutter là single-codebase UI, nhưng camera frame là dữ liệu lớn (1080p YUV ≈ 3MB/frame @ 30fps ≈ 90MB/s). Câu hỏi: phân tích frame ở đâu?

---

## Decision Drivers

- Phải đạt < 100ms p90 frame→hint trên máy tầm trung (go/no-go của sản phẩm)
- Battery/thermal: session camera 10 phút không throttle (NFR-2)
- Privacy: frame không rời thiết bị (NFR-3)
- Solo dev: chi phí maintain 2 nền tảng native phải tối thiểu
- MediaPipe/ML Kit SDK trưởng thành nhất ở native (Kotlin/Swift), bindings Dart chậm cập nhật

---

## Considered Options

### Option 1: Stream frame về Dart, xử lý bằng Dart/FFI plugins

Dùng `camera` plugin `startImageStream`, đưa từng frame qua platform channel về Dart, gọi TFLite qua FFI.

| Pros | Cons |
|------|------|
| Một ngôn ngữ duy nhất (Dart) | Copy 3MB/frame qua channel @30fps — chiếm CPU + GC pressure lớn |
| Dễ debug, hot reload | Latency channel + convert YUV→RGB ở Dart phá vỡ budget 100ms |
| Không cần viết Kotlin/Swift | Pin/nhiệt tệ; plugin bindings ML chậm cập nhật model mới |

### Option 2: Xử lý toàn bộ ở native side, gửi CHỈ kết quả (~1KB) về Dart

Native module (Kotlin/CameraX ImageAnalysis, Swift/AVCaptureVideoDataOutput) chạy MediaPipe/ML Kit ngay trên frame buffer (zero-copy), serialize `FrameAnalysis` JSON gọn qua EventChannel.

| Pros | Cons |
|------|------|
| Zero-copy frame access, inference native tốc độ tối đa | Phải viết + maintain 2 codebase native (Kotlin + Swift) |
| Payload qua channel ~1KB → latency channel ≤2ms | Debug pipeline khó hơn (native tooling) |
| MediaPipe/ML Kit dùng bản chính chủ, cập nhật nhanh | Contract Dart↔native phải giữ đồng bộ 2 bên |
| Detector Scheduler kiểm soát thermal ngay tại nguồn | |

### Option 3: Hybrid — detect native, composition ở Dart trên frame downscale

Native gửi frame downscale 320px về Dart để phân tích composition, pose vẫn native.

| Pros | Cons |
|------|------|
| Rule tuning composition nhanh (Dart hot reload) | Vẫn stream pixel qua channel (~100KB/frame) |
| | Hai đường dữ liệu → phức tạp hơn Option 2 mà không nhanh hơn |

---

## Decision Outcome

**Chosen Option:** Option 2 — Xử lý toàn bộ ở native side, chỉ gửi kết quả

**Rationale:** Driver số 1 (latency <100ms) và driver 2 (thermal) đều chỉ đạt được khi frame không rời native memory. Chi phí maintain 2 native module được giới hạn bằng cách: (1) native module chỉ làm detection — KHÔNG logic nghiệp vụ; (2) toàn bộ quyết định guidance nằm trong Rule Engine pure Dart, viết một lần; (3) contract `FrameAnalysis` được định nghĩa một chỗ (`app/lib/core/platform/`) và mirror sang native.

### Quantified Impact

| Metric | Option 1 (ước tính) | Option 2 (target) | Notes |
|--------|--------------------|--------------------|-------|
| Channel payload/frame | ~3MB (hoặc 100KB downscale) | ~1KB | |
| Frame→hint p90 | 150–300ms | < 100ms | Benchmark gate Sprint 1 |
| CPU copy overhead | Cao (mỗi frame) | ~0 (zero-copy analyzer) | |

---

## Consequences

**Positive:**
- Latency budget khả thi; pin/nhiệt kiểm soát tại Detector Scheduler
- Privacy by design: pixel không bao giờ vào Dart heap hay network
- Rule engine testable độc lập với camera (nhận `FrameAnalysis` giả lập)

**Negative:**
- Cần kỹ năng Kotlin + Swift; thay đổi contract phải sửa 3 nơi (Dart + 2 native)
- CI cho native module phức tạp hơn (cần macOS runner cho iOS)

**Risks:**
- Contract drift giữa Dart và native → mitigate: JSON schema test fixture chung, versioned payload (`schemaVersion` field)

---

## Validation

- [ ] Benchmark Sprint 1 tuần 1: pose 15fps + composition 5fps trên Pixel 6a / iPhone 12 đạt <100ms p90
- [ ] Thermal test 10 phút không throttle
- [x] Tech Strategy alignment confirmed
- [ ] Related plan: `docs/specs/spec-sprint-1.md`

---

## Links

- [PRD](../prd/PRD-shotmate-mvp.md) · [System Design](../design/system-design-shotmate.md) · [ADR-0003 Rule Engine](./0003-rule-engine-realtime-guidance.md) · [ADR-0006 ML Stack](./0006-on-device-ml-stack.md)

---

## Changelog

| Date | Author | Change |
|------|--------|--------|
| 2026-07-03 | Đạt Trần | Initial draft |
