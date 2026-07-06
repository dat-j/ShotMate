# ADR-0007: Native Inference Module sở hữu camera session (preview + analysis + capture)

## Metadata

**Status:** Accepted · **Date:** 2026-07-06 · **Deciders:** Đạt Trần · **Tags:** mobile, camera, architecture
**Related PRD:** [PRD-shotmate-mvp.md](../prd/PRD-shotmate-mvp.md) · **Supersedes:** N/A · **Superseded By:** N/A

**Tech Strategy:** ⚠️ Deviation — tech-strategy.md ghi "`camera` plugin cho preview/capture". ADR này thu hẹp: trên Android, native module sở hữu cả preview/capture (xem Rationale).

---

## Context

ADR-0001 chốt: frame được phân tích ở native (CameraX `ImageAnalysis`), không stream pixel về Dart. tech-strategy.md đồng thời ghi dùng `camera` plugin cho preview + capture.

Khi implement native module Sprint 1 (commit sau `d839b03`), phát hiện xung đột runtime: một camera vật lý **không thể** mở đồng thời bởi hai stack độc lập — `camera` plugin dùng Camera2 API trực tiếp, còn native module dùng CameraX (`ProcessCameraProvider`). Log thiết bị cho thấy `provider.bindToLifecycle(...)` của native gọi `unbindAll()` và **detach luôn Preview/ImageCapture của plugin**, hoặc hai bên tranh session tùy thứ tự khởi tạo và OEM. Kết quả: hoặc preview mất, hoặc ImageAnalysis không nhận frame — inference không chạy.

---

## Decision Drivers

- ADR-0001 bắt buộc ImageAnalysis chạy native → CameraX phải giữ được camera
- Preview + analysis + capture phải nhìn cùng một luồng frame (guidance realtime khớp ảnh chụp)
- Không được có hai owner của cùng một tài nguyên phần cứng (nguồn bug OEM-specific)
- iOS Sprint 1 chưa có native module → không được làm vỡ path hiện tại

---

## Considered Options

### Option 1: `camera` plugin sở hữu, native chỉ nhận frame plugin đẩy ra

Plugin mở camera, dùng `startImageStream` đưa frame cho native xử lý.

| Pros | Cons |
|------|------|
| Ít code native (không cần Preview/Capture) | **Vi phạm ADR-0001** (cấm `startImageStream`, cấm stream pixel qua channel) |
| Giữ nguyên CameraScreen | Copy frame qua channel — phá budget 100ms, chính là thứ ADR-0001 loại bỏ |

### Option 2: Native module sở hữu toàn bộ camera session

CameraX bind Preview + ImageAnalysis + ImageCapture cùng lúc trong một `ProcessCameraProvider`. Preview nhúng Flutter qua PlatformView (`AndroidView`); capture qua MethodChannel. Bỏ `camera` plugin khỏi CameraScreen trên Android.

| Pros | Cons |
|------|------|
| Một owner duy nhất — hết tranh chấp | Phải viết PlatformView + MethodChannel capture + wire lại Dart |
| Preview/analysis/capture cùng một session, cùng luồng frame | CameraScreen phải rẽ nhánh theo platform (Android native / iOS plugin) |
| Đúng tinh thần ADR-0001 (native là nguồn frame) | Native side gánh thêm lifecycle preview |

---

## Decision Outcome

**Chosen Option:** Option 2 — Native module sở hữu toàn bộ camera session.

**Rationale:** Option 1 mâu thuẫn trực tiếp ADR-0001 (driver latency <100ms). Khi native đã bắt buộc phải giữ CameraX cho ImageAnalysis, để nó giữ luôn Preview + ImageCapture là lựa chọn nhất quán và loại bỏ hoàn toàn lớp tranh chấp phần cứng. `camera` plugin vẫn giữ trong pubspec làm fallback cho iOS (chưa có native module) — CameraScreen rẽ nhánh qua `NativeCamera.isSupported`.

Đây là **thu hẹp** tech-strategy, không đảo ngược: plugin vẫn là đường cho platform chưa có native module.

---

## Consequences

**Positive:**
- Hết xung đột camera; preview + analysis + capture cùng một session (đã verify trên thiết bị Android 16: `preview + analysis + capture now ATTACHED`)
- Ảnh chụp và frame phân tích đến từ đúng một luồng → guidance khớp ảnh
- Nhất quán ADR-0001

**Negative:**
- CameraScreen có hai path (native Android / plugin iOS) — phải test cả hai khi iOS module xong
- Khi implement iOS native module, phải làm PlatformView + capture channel tương đương (contract `shotmate/camera_preview`, `shotmate/camera_control`)

**Risks:**
- PlatformView (AndroidView) có chi phí render/compositing → theo dõi trong benchmark gate; nếu ảnh hưởng latency, cân nhắc `TextureView`/hybrid composition

---

## Validation

- [x] Verify trên thiết bị Android 16: Preview + ImageAnalysis + ImageCapture ATTACHED cùng lúc, preview render, overlay chạy trên payload native, không crash
- [x] `flutter analyze` 0 issue · `flutter test` 80/80 pass
- [ ] Benchmark gate: đo latency có PlatformView preview
- [ ] iOS: implement native module tương đương (path plugin hiện là tạm)

---

## Links

- [ADR-0001 Native frame processing](./0001-native-side-frame-processing.md) · [ADR-0006 ML Stack](./0006-on-device-ml-stack.md) · [tech-strategy.md](../../.claude/rules/tech-strategy.md)

---

## Changelog

| Date | Author | Change |
|------|--------|--------|
| 2026-07-06 | Đạt Trần (swarm) | Initial — phát sinh khi implement native module Sprint 1, giải xung đột camera plugin ↔ CameraX |
