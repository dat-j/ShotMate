# Sprint 1 — Status & Handoff (Dart layer + native runner done)

<!--
Sprint Status / Handoff Note
Filename: docs/specs/sprint-1-status.md
Owner: Builder
Purpose: Tổng hợp việc đã xong (commit b5568dc + d839b03) + việc còn lại để triển khai tiếp Sprint 1.
Related: spec-sprint-1.md (spec gốc), roadmap.md (Phase 1)
-->

## Metadata

**Date:** 2026-07-06 (cập nhật: scaffold native runner)
**Commit:** `b5568dc` (Dart layer, đã push) · `d839b03` (native runner + camera permissions — **local, chưa push**, xem §3)
**Quality gate:** `flutter analyze` 0 issue · `flutter test` 80/80 pass · debug APK build + chạy trên thiết bị thật OK

---

## 1. Đã hoàn thành (Dart/Flutter layer)

### Domain & data

| Hạng mục | Spec | File chính | Test |
|----------|------|-----------|------|
| Rule engine v0 + hysteresis (có sẵn từ bootstrap, đã verify + sửa 1 fixture sai) | FR-S1-3 | `features/coach/domain/coach_rule_engine.dart` | 13 golden test |
| PhotoScorer: lighting/focus/background, threshold tunable một chỗ | FR-S1-5 | `features/score/domain/photo_scorer.dart` | 17 test |
| Drift DB provider (LazyDatabase, app-private file) | ADR-0005 | `core/di/database_provider.dart` | — |
| PhotosRepository (UUID client-side, phân trang 30) | FR-S1-6, ADR-0002 | `features/history/data/photos_repository.dart` | 4 test |
| AnalysesRepository / ScoresRepository (clamp 2 lớp, join photo+score mới nhất) | FR-S1-5/6 | `features/{history,score}/data/` | 9 test |
| CreditRepository: quota 10/ngày, reset-on-read theo ngày địa phương | FR-S1-8, BR-4 | `features/history/data/credit_repository.dart` | 9 test |
| PerfTracker: sliding window 10s, p50/p90, `now` truyền ngoài | FR-S1-7 | `features/coach/domain/perf_tracker.dart` | 12 test |
| CaptureOrchestrator: persist → credit check → score → record (EC-5 đúng spec: hết quota vẫn lưu ảnh) | FR-S1-5, BR-4 | `features/camera/domain/capture_orchestrator.dart` | 5 test |
| CaptureDebouncer (EC-7: chống double-capture) | EC-7 | `features/camera/domain/capture_debouncer.dart` | 2 test |

### UI & wiring

| Hạng mục | Spec | Ghi chú |
|----------|------|---------|
| CameraScreen: `camera` plugin thật, permission flow (EC-3, `permission_handler`), lifecycle-aware, nút chụp disable khi đang xử lý | FR-S1-1 | KHÔNG `startImageStream` (ADR-0001) |
| CoachOverlay: grid thirds + skeleton painter + max 2 hint + rating sao, toggle từ settings | FR-S1-4 | fade 150ms giữ nguyên |
| ScoreScreen: Drift lookup theo photoId, 4 chiều + progress bar, trạng thái hết quota + CTA placeholder | FR-S1-5, EC-5 | 4 widget test |
| HistoryScreen: infinite scroll 30/trang, thumbnail fallback khi mất file, "Chưa có điểm" khi score null | FR-S1-6 | 7 widget test |
| SettingsScreen + route `/settings`: toggle grid/skeleton/Perf HUD (HUD chỉ hiện ở debug build) | FR-S1-4/7 | providers: `showGridProvider`, `showSkeletonProvider`, `showPerfHudProvider` |
| PerfHud widget: per-detector fps/p50/p90 + frame→hint p50/p90, mount `if (kDebugMode && showPerfHud)` | FR-S1-7 | 2 widget test |
| Theme tập trung: `core/theme/` (colors/spacing/theme), thay hết màu hardcode | — | commit `13f0ed2` |

---

## 2. Việc còn lại của Sprint 1 (theo thứ tự nên làm)

### 2.1. Scaffold native runner — ✅ XONG (commit `d839b03`, 2026-07-06)

`flutter create . --platforms android,ios --org com.shotmate` đã sinh runner đầy đủ (61 file, `lib/` giữ nguyên). Đã cấu hình:

- Android: `CAMERA` uses-permission + `uses-feature` camera/autofocus; `minSdk = maxOf(24, flutter.minSdkVersion)`; label `ShotMate`
- iOS: `NSCameraUsageDescription` + `NSPhotoLibraryAddUsageDescription` trong Info.plist
- Xoá README template rỗng do `flutter create` sinh ra

**Verify:** `flutter analyze` 0 issue · `flutter test` 80/80 pass · `assembleDebug` build OK · cài + launch trên thiết bị thật (Xiaomi, Android 16 / API 36) **không crash** — logcat cho thấy camera plugin khởi tạo được session (`updateSessionParams ... com.shotmate.shotmate_app`).

**Còn nợ:** smoke test bằng tay full flow (preview → chụp → score → history) — cần thao tác UI trên máy; scaffold + camera-init đã pass.

### 2.2. Native Inference Module (FR-S1-2) — khối lượng lớn nhất còn lại

Contract đã chốt trong `app/{android,ios}/NATIVE_MODULE.md` và `frame_analysis.dart` (source of truth, schemaVersion 1):

- **Android (Kotlin):** CameraX ImageAnalysis + MediaPipe pose_landmarker_lite (15fps, GPU delegate) + ML Kit ODT (5fps) + exposure sampler (5fps) → EventChannel `shotmate/frame_analysis`
- **iOS (Swift):** AVCaptureVideoDataOutput + cùng detector stack
- Detector Scheduler + thermal throttling (EC-4), rotation handling (EC-6)
- Sharpness (Laplacian variance) + background edge density ngay sau capture → thay 2 placeholder trong `capture_orchestrator.dart` (đã đánh dấu TODO)
- Emit `inferenceLatencyMs` per-detector → feed `PerfTracker` (điểm nối đã có sẵn, xem comment trong `perf_hud.dart`)

### 2.3. Benchmark gate <100ms p90 (go/no-go — deadline roadmap: 2026-07-11)

Cần 2.1 + 2.2 xong + thiết bị tham chiếu (Pixel 6a / iPhone 12 — **chưa xác nhận có máy**, xem Open Questions trong spec). Perf HUD đã sẵn sàng đo.

### 2.4. Việc nhỏ còn nợ

- [ ] Firebase Analytics events (`camera_session_start`, `hint_shown`, `photo_captured`, `photo_scored`, `quota_exhausted`) — cần `flutterfire configure` trước (ghi chú sẵn trong pubspec.yaml)
- [ ] EC-2 (multi-person: track box lớn nhất, giữ target 1s) — logic thuộc native module
- [ ] Settings toggles chưa persist (StateProvider in-memory; cân nhắc lưu Drift/SharedPreferences nếu muốn giữ qua restart — spec không bắt buộc)
- [ ] Manual test checklist trên thiết bị cho các EC device-behavior (EC-3, EC-4, EC-6)

---

## 3. Ghi chú môi trường dev (host hiện tại)

- Flutter SDK: `~/Documents/flutter_SDK/flutter/bin` — đã thêm vào `~/.zshrc`
- Drift test cần `libsqlite3.so`: host thiếu symlink dev — đã tạo `~/.local/lib/libsqlite3.so → libsqlite3.so.0` + `LD_LIBRARY_PATH` trong `~/.zshrc` (không cần sudo). CI Linux sẽ cần `libsqlite3-dev` hoặc workaround tương tự.
- `*.g.dart`/`*.freezed.dart` gitignored — chạy `dart run build_runner build -d` sau khi clone.
- **Thiết bị test:** Xiaomi (Android 16 / API 36, arm64) qua adb-wifi. Lưu ý: adb liệt kê theo địa chỉ IP (`192.168.x.x:port`), không phải serial `2210132C` → khi `adb -s` phải dùng địa chỉ IP. `flutter install` mặc định tìm `app-release.apk`; cài debug bằng `adb install -r build/app/outputs/flutter-apk/app-debug.apk`.
- **Push remote:** origin là HTTPS (`github.com/dat-j/ShotMate.git`) nhưng host không có credential/token → `git push` fail (`could not read Username`). Commit `d839b03` đang nằm ở local. Cần Đạt cấu hình PAT/SSH rồi push tay.

## 4. Quyết định/deviation trong lúc làm

| Quyết định | Lý do |
|-----------|-------|
| Sửa test fixture "well-composed" (box 4% khung → 16%) thay vì sửa scoring | Fixture mâu thuẫn với chính spec (subjectMinArea 8%); công thức score đúng |
| Focus/background input = placeholder (50.0 / 0.3) có TODO | Native detector chưa tồn tại; giữ PhotoScorer pure + testable, thay số khi native xong |
| Hết quota: không insert Score row (thay vì insert rồi ẩn) | Đơn giản hơn, history/score screen phân biệt qua `score == null` (EC-5) |
| Settings = StateProvider in-memory, chưa persist | Spec không yêu cầu persist; tránh nở scope |
| `flutter create --org com.shotmate` → applicationId `com.shotmate.shotmate_app` | Chưa có bundle ID chính thức; đổi trước khi submit store (Sprint 3) |
| `minSdk = maxOf(24, flutter.minSdkVersion)` thay vì hardcode 24 | Giữ ngưỡng ≥ 24 (camera + MediaPipe) nhưng tự nâng nếu Flutter yêu cầu cao hơn |
