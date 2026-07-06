/// Ổn định scene classifier (spec-sprint-2 Business Rule 6).
///
/// Native trả `sceneType` mỗi frame (1fps) có thể nhấp nháy. Chỉ công bố scene
/// mới sau [requiredStreak] mẫu liên tiếp cùng class (mặc định 3 ≈ 3s) → chống
/// zoom chip / angle hint nhảy (EC-S2-3).
///
/// Stateful có chủ đích (giống HintPrioritizer): giữ scene công bố + streak
/// hiện tại. Pure Dart, không I/O — test deterministic bằng cách feed chuỗi.
library;

import 'frame_analysis.dart';

class SceneStabilizer {
  SceneStabilizer({this.requiredStreak = 3});

  final int requiredStreak;

  SceneType _published = SceneType.unknown;
  SceneType? _candidate;
  int _streak = 0;

  /// Scene đang được công bố (đã qua ngưỡng ổn định).
  SceneType get published => _published;

  /// Nạp 1 quan sát scene thô, trả scene công bố sau khi cập nhật.
  SceneType observe(SceneType raw) {
    if (raw == SceneType.unknown) {
      // unknown không reset streak của candidate hợp lệ đang tích luỹ, nhưng
      // cũng không tự trở thành candidate — giữ scene công bố hiện tại.
      _candidate = null;
      _streak = 0;
      return _published;
    }
    if (raw == _candidate) {
      _streak++;
    } else {
      _candidate = raw;
      _streak = 1;
    }
    if (_streak >= requiredStreak) {
      _published = raw;
    }
    return _published;
  }

  void reset() {
    _published = SceneType.unknown;
    _candidate = null;
    _streak = 0;
  }
}
