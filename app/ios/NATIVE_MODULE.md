# iOS Native Inference Module (Sprint 1)

> Thư mục ios/ runner đầy đủ sẽ được sinh bởi `flutter create` (xem README gốc).
> File này là contract cho module inference — implement trong `ios/Runner/`.

## Trách nhiệm (ADR-0001)

- `AVCaptureVideoDataOutput` + `CMSampleBuffer` xử lý trực tiếp (zero-copy tối đa)
- Detector Scheduler: pose 15fps, composition 5fps, scene 1fps
- Serialize kết quả → `FlutterEventChannel` tên `shotmate/frame_analysis`
- **KHÔNG** gửi pixel qua channel; **KHÔNG** logic nghiệp vụ

## Dependencies (Podfile / SPM)

```ruby
pod 'MediaPipeTasksVision'      # pose_landmarker_lite
pod 'GoogleMLKit/ObjectDetection'
pod 'GoogleMLKit/FaceDetection'
pod 'GoogleMLKit/ImageLabeling' # Sprint 2: scene
```

## Payload contract

Giống Android — source of truth: `app/lib/features/coach/domain/frame_analysis.dart` (schemaVersion 1). Xem `app/android/NATIVE_MODULE.md` cho JSON mẫu.

## Thermal (spec EC-4)

`ProcessInfo.processInfo.thermalState` ≥ `.serious` → pose 5fps, tắt exposure sampler, emit `"throttled": true`.

## Ghi chú

- Horizon angle: `CMMotionManager` (gravity vector) + edge detect nhẹ khi cần đường chân trời thực
- Camera permission string: `NSCameraUsageDescription` giải thích rõ frame chỉ xử lý on-device (NFR-3 — điểm bán hàng privacy, ghi thẳng vào copy)
