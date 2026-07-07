# Plan: Hint realtime trực quan + AI Review có annotation trên ảnh

## Context

Backend đã deploy đầy đủ lên GCP, luồng camera → hint → chụp → Review AI đã hoạt động end-to-end (đã fix hàng loạt bug: Dockerfile, worker probe, SMTP auth, GCS storage config, deep-link crash, và bug status-casing khiến "Review AI" quay vô hạn dù job đã xong).

Sau khi thấy luồng hoạt động, người dùng (chủ dự án) nhận ra 2 khoảng cách so với kỳ vọng ban đầu ("app mở lên chụp ảnh sẽ có hint hỗ trợ cầm máy, nghiêng bao nhiêu, dáng người thế nào"):

1. **Hint realtime hiện tại chỉ là text chip nhỏ** ("Nghiêng máy 5°", "Di chuyển sang trái") — không trực quan, khó đọc trong lúc đang giữ máy ngắm khung hình. Rule engine + dữ liệu (pose landmarks, subject box, horizon angle) đã có sẵn và chạy đúng 100% offline (ADR-0003) — vấn đề thuần là **cách hiển thị**, không phải thiếu dữ liệu.
2. **Review AI (sau khi chụp) chỉ trả về text** (điểm số + giải thích + gợi ý dạng câu) — muốn có annotation trực quan (khung khoanh vùng vấn đề) vẽ ngay trên ảnh đã chụp, không chỉ đọc chữ.

Đã xác nhận với người dùng: làm **Feature A (hint realtime trực quan) trước**, **Feature B (AI Review annotation) sau**. Cả 4 kiểu overlay trong Feature A đều được chọn: mũi tên chỉ hướng, thanh mức nghiêng (bubble level), khung mục tiêu thirds (reticle), và skeleton nối xương (thay chấm rời, bật mặc định — không còn là debug toggle).

Ràng buộc kiến trúc bắt buộc phải giữ (đọc từ ADR-0001, ADR-0003, CLAUDE.md):

- **Không có LLM/inference nào trong vòng lặp realtime** — mọi overlay mới chỉ là _rendering_ từ dữ liệu `FrameAnalysis`/`CoachHint` đã có, không thêm model call.
- **Pixel không rời native side** — chỉ dùng dữ liệu structured đã qua EventChannel.
- **Rule engine giữ pure, deterministic, coverage ≥ 90%** — logic tính điểm mục tiêu thirds phải nằm trong rule engine (đã chốt với người dùng), có golden test kèm theo.
- Không cần schema bump native (Phase 2 trong thiết kế gốc) cho bản đầu — dữ liệu `FrameAnalysis` v2 hiện tại (pose landmarks x/y, subjectBox, horizonAngleDeg, pitchDeg) đã đủ cho toàn bộ 4 loại overlay.

---

## Phase A — Hint realtime trực quan (ưu tiên trước)

### A1. Rule engine: thêm target point cho thirds rule

`app/lib/features/coach/domain/coach_hint.dart`:

- Thêm field tùy chọn vào `CoachHint`: `final ({double x, double y})? targetPoint` (normalized [0,1]) — điểm giao thirds gần nhất mà subject nên di chuyển tới. Null cho các hint không có khái niệm "điểm đích" (horizon, chin, smile...).

`app/lib/features/coach/domain/coach_rule_engine.dart`:

- `_thirdsRule` hiện đã tính `bestDx`/`bestDy` từ vòng lặp qua 4 giao điểm thirds nhưng chỉ dùng để suy ra `direction`. Sửa để giữ lại tọa độ giao điểm gần nhất (`ix`, `iy` tại điểm có `bestDist` nhỏ nhất) và gán vào `CoachHint.targetPoint`.
- Test: cập nhật golden fixtures liên quan tới `thirds_offset` trong `app/test/features/coach/domain/coach_rule_engine_test.dart` (hoặc file tương đương) để assert `targetPoint` đúng tọa độ giao điểm kỳ vọng cho từng fixture hiện có.

### A2. Camera screen: truyền thêm dữ liệu vào overlay

`app/lib/features/camera/presentation/camera_screen.dart`:

- Hiện chỉ truyền `poseLandmarks` và `throttled` vào `CoachOverlay`. Bổ sung truyền: `analysis?.horizonAngleDeg`, `analysis?.pitchDeg`, `analysis?.subjectBox`.

### A3. CoachOverlay: 4 painter mới + nâng cấp skeleton

`app/lib/features/camera/presentation/coach_overlay.dart` (tách các painter mới sang file riêng nếu file này quá dài — gợi ý `coach_overlay_painters.dart` cùng thư mục):

1. **Mũi tên chỉ hướng** (`_DirectionArrowPainter`): vẽ mũi tên lớn, rõ ràng ở giữa/gần rìa màn hình theo `CoachHint.direction` (left/right/up/down/tiltLeft/tiltRight), độ dài/độ đậm tỉ lệ với `hint.metric`. `forward`/`backward` (tiến/lùi máy) không có hướng 2D thật — vẽ dạng vòng tròn co giãn (breathing circle: to dần nếu cần lùi, nhỏ dần nếu cần tiến) thay vì mũi tên. Đây là hint nổi bật nhất, thay thế phần lớn vai trò của `_HintChip` hiện tại (giữ `_HintChip` làm text phụ trợ bên dưới mũi tên cho rõ nghĩa, không xóa hẳn).
2. **Thanh mức nghiêng** (`_TiltGaugePainter`): bubble-level ngang, xoay theo `horizonAngleDeg`; chuyển xanh lá khi nằm trong `CoachThresholds.horizonOffDeg`, đỏ/vàng khi lệch. Nếu có `pitchDeg` (scene portrait/food), thêm chỉ báo trục phụ (tick ngang) cho góc ngẩng/cúi máy — tái dùng đúng logic dải "đẹp" đã có trong `_angleRule`.
3. **Khung mục tiêu thirds** (`_TargetReticlePainter`): vẽ 4 giao điểm thirds mờ, khi có `thirds_offset` hint active thì highlight giao điểm gần nhất (dùng `CoachHint.targetPoint` từ A1) bằng vòng tròn/marker nổi bật, đồng thời vẽ khung `subjectBox` hiện tại (outline nhẹ) để người dùng thấy trực tiếp "đang ở đây → cần tới đây".
4. **Skeleton nối xương**: nâng cấp `_SkeletonPainter` từ `drawCircle` từng điểm sang `drawLine` theo danh sách cạnh chuẩn BlazePose 33-điểm (const list các cặp index). Khi `raise_chin` hint đang active, tô màu nổi bật đoạn xương mũi–vai để làm rõ hint đang nói về gì.

- Đổi `showSkeleton` từ mặc định `false` sang mặc định `true` trong `app/lib/features/settings/application/settings_providers.dart`; đổi copy trong `settings_screen.dart` từ "Hiển thị skeleton debug" sang tên thân thiện hơn (vd "Hiển thị hướng dẫn dáng đứng").

### A4. Testing Phase A

- Unit test thuần cho phần toán học mới trong rule engine (`targetPoint`) — mở rộng golden fixtures hiện có, không viết fixture mới từ đầu.
- Widget/golden test cho các painter mới (`app/test/features/camera/presentation/coach_overlay_test.dart` — file mới): dựng `CoachState`/`FrameAnalysis` cố định, `expectLater(..., matchesGoldenFile(...))` cho vài trường hợp tiêu biểu (nghiêng nhiều, lệch thirds trái/phải, đủ 33 landmark).
- `flutter analyze` 0 issue + `flutter test` pass toàn bộ (không chỉ file mới) — quality gate bắt buộc theo CLAUDE.md trước khi coi Phase A xong.
- Manual verify trên thiết bị thật (đã có sẵn qua adb, thiết bị `f798443c`): build APK debug, cầm máy nghiêng thử, quan sát mũi tên/gauge/reticle/skeleton phản ứng đúng hướng và mượt (không giật, không trễ cảm nhận được — dùng Perf HUD sẵn có để xác nhận frame→hint vẫn <100ms p90, không có painter nào làm phình thời gian).

---

## Phase B — AI Review có annotation trực quan (sau khi Phase A xong và verify)

### B1. Backend: mở rộng schema + prompt

`backend/src/modules/ai-review/ai-review.provider.ts`:

- Thêm field tùy chọn vào `reviewResultSchema`: `annotations: z.array(z.object({ label: z.string(), box: z.object({ x, y, width, height } each 0-1), issue: z.string() })).max(5).optional().default([])` — mirror đúng convention của `suggestions` (default rỗng, không nullable) để Dart không phải xử lý nullable riêng.
- Tách `REVIEW_SYSTEM_PROMPT` hiện tại (giữ nguyên, dùng chung) + thêm hằng số mới `SPATIAL_ANNOTATION_PROMPT_ADDENDUM` yêu cầu model trả bounding box **normalized 0-1 dạng x/y/width/height** (chỉ định rõ format để khỏi phải remap từ convention khác của Gemini).

`backend/src/modules/ai-review/gemini.provider.ts`, `vertex.provider.ts`:

- Nối thêm `SPATIAL_ANNOTATION_PROMPT_ADDENDUM` vào phần text gửi kèm ảnh.

`backend/src/modules/ai-review/claude.provider.ts`:

- Không đổi gì — không thêm addendum, Claude sẽ tự nhiên không trả `annotations`, schema `.optional().default([])` chấp nhận việc này không cần try/catch riêng. Thêm 1 dòng comment ngắn giải thích tại sao cố ý bỏ qua (tránh người sau "sửa" nhầm thành thêm addendum).

### B2. Backend testing

- `ai-review.service.spec.ts`: thêm case fake provider trả `annotations` và case không trả gì, xác nhận `AiReviewService.review()` pass-through nguyên vẹn (service không cần đổi logic).
- Test schema validation riêng cho `annotations` (bounds 0-1, max 5 items, absent OK) — thêm vào file test provider hiện có hoặc file mới `ai-review.provider.spec.ts` nếu chưa có.
- `npm run build` + `npm test` pass (quality gate CLAUDE.md).

### B3. Dart: model + UI

`app/lib/core/geometry/normalized_box.dart` (file mới): value type `NormalizedBox { left, top, width, height }` + `fromJson`/`toJson` — dùng chung cho cả `SubjectBox` (coach) và annotation box (review), tránh trùng lặp hoặc cross-feature import lộn xộn. Cân nhắc: nếu refactor `SubjectBox` hiện tại sang dùng type này tốn công quá, có thể để `SubjectBox` giữ nguyên riêng và chỉ dùng `NormalizedBox` cho annotation — không bắt buộc hợp nhất ngay, miễn không tạo thêm nợ kỹ thuật rõ rệt.

`app/lib/features/review/domain/review_result.dart`:

- Thêm `@freezed class ReviewAnnotation { label, box (NormalizedBox), issue }` + `fromJson`/`toJson`.
- Thêm `@Default(<ReviewAnnotation>[]) List<ReviewAnnotation> annotations` vào `ReviewResult`.
- Chạy `dart run build_runner build -d` để regen `.freezed.dart`/`.g.dart`.

`app/lib/features/review/presentation/review_result_view.dart`:

- Theo quyết định người dùng: **ảnh có annotation hiển thị RIÊNG trong phần kết quả Review AI** (không thay thế thumbnail gốc ở đầu Score Screen). Cần thread `photo.filePath` xuống `_ReviewAiSection` → `ReviewResultView` (hiện chỉ nhận `photoId`).
- `ReviewResultView` thêm block ảnh mới ở đầu phần kết quả: `ClipRRect > AspectRatio > Stack[Image.file(filePath), CustomPaint(painter: _AnnotationOverlayPainter(annotations))]` — tái dùng đúng cấu trúc `_PhotoThumbnail` đã có trong `score_screen.dart` làm mẫu.
- `_AnnotationOverlayPainter`: vẽ khung chữ nhật cho mỗi `annotation.box` (normalized → Rect theo canvas size, giống hệt phép biến đổi tọa độ đã dùng ở Phase A cho reticle/subjectBox — có thể trích thành helper dùng chung `lib/core/rendering/normalized_box_painter_utils.dart` nếu thấy lặp code đáng kể), kèm label chip nhỏ cạnh mỗi khung (style theo `_HintChip` cho nhất quán hình ảnh giữa 2 feature).
- Khi `annotations` rỗng (Claude, hoặc Gemini/Vertex không trả gì lần đó): không hiển thị block ảnh annotation, giữ nguyên UI text-only như hiện tại — không có khoảng trống/vỡ layout.

`app/lib/features/score/presentation/score_screen.dart`:

- Sửa `_ReviewAiSection` để nhận và truyền thêm `photoFilePath` xuống `ReviewResultView`.

### B4. Testing Phase B

- Unit test `ReviewResult.fromJson` round-trip có/không có `annotations` (file test đã có cho `review_result.dart` — mở rộng, không tạo mới nếu đã tồn tại).
- Widget/golden test cho `_AnnotationOverlayPainter` tương tự cách làm ở A4.
- `flutter analyze` + `flutter test` pass.
- Manual verify end-to-end: chụp ảnh thật trên thiết bị → bấm Review AI (dùng provider Vertex đang hoạt động) → xác nhận khung annotation hiện đúng vị trí hợp lý trên ảnh, và test riêng trường hợp không có annotation (ép fail Gemini/Vertex tạm thời hoặc set `AI_REVIEW_PRIMARY` sang thử) để chắc UI fallback không vỡ.

---

## Việc không làm trong plan này (đã loại trừ có chủ đích)

- **Không bump `schemaVersion` native lên 3** (thêm visibility/z-depth per-landmark) — dữ liệu x/y hiện tại đủ cho cả 4 loại overlay Phase A. Chỉ cân nhắc sau nếu skeleton nối xương bị giật/sai do điểm confidence thấp mà không lọc được.
- **Không tạo ảnh mới bằng image-generation model** — chỉ vẽ overlay ở client từ tọa độ model trả về, không sinh ảnh AI vẽ đè lên ảnh gốc (chi phí/độ phức tạp không tương xứng).
- **Không đổi `AI_REVIEW_PRIMARY` hay thay `ANTHROPIC_API_KEY` thật** trong plan này — việc đó độc lập, đã ghi nhận riêng, không phụ thuộc Phase A/B.

---

## Xác minh tổng thể khi xong cả 2 phase

1. `cd app && flutter analyze && flutter test` — 0 issue, pass toàn bộ.
2. `cd backend && npm run build && npm test` — pass toàn bộ.
3. Build APK debug trỏ Cloud Run, cài lên thiết bị thật (`adb install -r`), test tay: cầm máy nghiêng → thấy gauge phản ứng; đưa subject lệch thirds → thấy mũi tên + reticle chỉ đúng hướng; có người trong khung → thấy skeleton nối xương mượt; chụp ảnh → bấm Review AI → thấy khung annotation trên ảnh khi provider là Vertex.
4. Perf HUD xác nhận frame→hint vẫn <100ms p90 sau khi thêm painter (không regression hiệu năng).
