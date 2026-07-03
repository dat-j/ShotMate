# Android Native Inference Module (Sprint 1)

> Thư mục android/ runner đầy đủ sẽ được sinh bởi `flutter create` (xem README gốc).
> File này là contract cho module inference — implement trong `android/app/src/main/kotlin/`.

## Trách nhiệm (ADR-0001)

- CameraX `ImageAnalysis` use case (KHÔNG dùng `startImageStream` của Flutter)
- Chạy detectors theo Detector Scheduler (throttle: pose 15fps, composition 5fps, scene 1fps)
- Serialize kết quả → EventChannel `shotmate/frame_analysis`
- **KHÔNG BAO GIỜ** đẩy pixel/bitmap qua channel. **KHÔNG** logic nghiệp vụ (quyết định hint là việc của Rule Engine Dart)

## Dependencies (build.gradle)

```kotlin
implementation("androidx.camera:camera-camera2:<latest>")
implementation("androidx.camera:camera-lifecycle:<latest>")
implementation("com.google.mediapipe:tasks-vision:<latest>")        // pose_landmarker_lite
implementation("com.google.mlkit:object-detection:<latest>")
implementation("com.google.mlkit:face-detection:<latest>")
implementation("com.google.mlkit:image-labeling:<latest>")          // Sprint 2: scene
```

## Payload contract (schemaVersion 1)

Mirror của `app/lib/features/coach/domain/frame_analysis.dart` — file Dart là source of truth:

```json
{
  "schemaVersion": 1,
  "timestampMs": 1730000000000,
  "horizonAngleDeg": -4.2,
  "subjectBox": {"left": 0.1, "top": 0.2, "width": 0.3, "height": 0.5},
  "subjectConfidence": 0.87,
  "hasPerson": true,
  "poseLandmarks": [[0.5, 0.3], "... 33 điểm [x,y] normalized"],
  "exposure": {"meanLuma": 128.0, "clippedHighlightsPct": 1.2, "clippedShadowsPct": 0.4},
  "inferenceLatencyMs": {"pose": 22, "composition": 9}
}
```

## Thermal (spec EC-4)

Lắng nghe `PowerManager.addThermalStatusListener`; state ≥ SEVERE → pose 5fps, tắt exposure sampler, emit field `"throttled": true`.
