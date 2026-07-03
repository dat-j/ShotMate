/// Hint hiển thị trên overlay + trạng thái coach tổng hợp.
library;

/// Thứ tự = độ ưu tiên (spec-sprint-1 Business Rule 1).
enum HintSeverity { critical, important, polish }

enum HintDirection { left, right, up, down, forward, backward, tiltLeft, tiltRight, none }

class CoachHint {
  const CoachHint({
    required this.id,
    required this.severity,
    required this.message,
    this.direction = HintDirection.none,
    this.metric = 0,
  });

  /// Ổn định theo rule (vd: 'horizon_tilt') — dùng cho hysteresis + analytics.
  final String id;
  final HintSeverity severity;

  /// ≤ 30 ký tự (spec FR-S1-4).
  final String message;
  final HintDirection direction;

  /// Giá trị metric gây ra hint (độ nghiêng, % lệch...) — phục vụ debug/HUD.
  final double metric;

  @override
  String toString() => 'CoachHint($id, $severity, "$message")';
}

class CoachState {
  const CoachState({required this.hints, required this.compositionScore});

  /// Đã qua prioritizer: tối đa 2, sort theo severity.
  final List<CoachHint> hints;

  /// [0,100] — rating sao = round(score/20), floor 1 (Business Rule 5).
  final int compositionScore;

  int get ratingStars {
    final stars = (compositionScore / 20).round();
    return stars < 1 ? 1 : (stars > 5 ? 5 : stars);
  }

  static const empty = CoachState(hints: [], compositionScore: 0);
}
