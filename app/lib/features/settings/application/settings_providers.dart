/// State toggles cho SettingsScreen (spec-sprint-1 FR-S1-4, FR-S1-7).
///
/// Các provider dưới đây là nguồn sự thật duy nhất cho việc hiển thị
/// grid rule-of-thirds / skeleton debug / Perf HUD trên camera overlay.
/// Chúng CHỈ gate rendering ở nơi khác (camera_screen.dart / coach_overlay.dart /
/// perf_hud.dart) — việc wiring conditional rendering đó nằm ngoài scope
/// của settings feature, xem TODO ở các file đó.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Hiển thị lưới rule-of-thirds trên coach overlay. Mặc định bật
/// (spec FR-S1-4: "grid rule-of-thirds (bật/tắt được)").
final showGridProvider = StateProvider<bool>((ref) => true);

/// Hiển thị skeleton dots (pose landmarks) — debug visualization, mặc định
/// tắt (spec FR-S1-4: "skeleton dots ... debug visualization, toggle trong
/// settings").
final showSkeletonProvider = StateProvider<bool>((ref) => false);

/// Hiển thị Perf HUD (fps/latency per-detector, frame→hint p50/p90) — chỉ
/// có ý nghĩa ở debug build (spec FR-S1-7: "Perf HUD (debug builds)").
/// Caller phải tự kiểm tra `kDebugMode` trước khi đọc provider này để mount
/// widget — xem `perf_hud.dart`.
final showPerfHudProvider = StateProvider<bool>((ref) => false);
