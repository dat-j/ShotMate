/// Rule engine v0 — trái tim của ShotMate (ADR-0003).
///
/// Pure function: cùng (FrameAnalysis, activeHintIds) luôn cho cùng output.
/// Không I/O, không async, không phụ thuộc Flutter. Hysteresis được làm
/// deterministic bằng cách nhận tập hint đang active làm input thay vì
/// giữ state nội bộ (spec-sprint-1 Business Rule 2).
library;

import 'dart:math' as math;

import 'coach_hint.dart';
import 'frame_analysis.dart';

/// Ngưỡng khởi điểm theo spec-sprint-1 FR-S1-3 — giá trị sẽ tuning thực địa,
/// giữ tất cả ở một chỗ (spec Open Questions).
class CoachThresholds {
  const CoachThresholds({
    this.horizonOnDeg = 3.0,
    this.horizonOffDeg = 1.5,
    this.horizonCriticalDeg = 7.0,
    this.thirdsOnOffset = 0.15,
    this.thirdsOffOffset = 0.10,
    this.subjectMinArea = 0.08,
    this.subjectCutEdgePct = 0.02,
    this.minSubjectConfidence = 0.5,
  });

  final double horizonOnDeg;
  final double horizonOffDeg;
  final double horizonCriticalDeg;

  /// Lệch giao điểm thirds gần nhất, tỷ lệ theo bề rộng khung.
  final double thirdsOnOffset;
  final double thirdsOffOffset;
  final double subjectMinArea;
  final double subjectCutEdgePct;
  final double minSubjectConfidence;

  static const defaults = CoachThresholds();
}

class CoachRuleEngine {
  const CoachRuleEngine({this.thresholds = CoachThresholds.defaults});

  final CoachThresholds thresholds;

  /// [activeHintIds]: các hint đang hiển thị từ lần đánh giá trước —
  /// dùng ngưỡng OFF thay vì ON cho các rule này (hysteresis).
  CoachState evaluate(
    FrameAnalysis frame, {
    Set<String> activeHintIds = const {},
  }) {
    final hints = <CoachHint>[
      ...?_horizonRule(frame, activeHintIds),
      ..._subjectRules(frame, activeHintIds),
    ];
    return CoachState(
      hints: hints,
      compositionScore: _compositionScore(frame),
    );
  }

  // --- Rules ---------------------------------------------------------------

  List<CoachHint>? _horizonRule(FrameAnalysis frame, Set<String> active) {
    final angle = frame.horizonAngleDeg;
    if (angle == null) return null;
    final threshold = active.contains('horizon_tilt')
        ? thresholds.horizonOffDeg
        : thresholds.horizonOnDeg;
    if (angle.abs() <= threshold) return null;
    final rounded = angle.abs().round();
    return [
      CoachHint(
        id: 'horizon_tilt',
        severity: angle.abs() > thresholds.horizonCriticalDeg
            ? HintSeverity.critical
            : HintSeverity.important,
        // Máy nghiêng phải (angle > 0) → chỉnh về trái.
        direction:
            angle > 0 ? HintDirection.tiltLeft : HintDirection.tiltRight,
        message: 'Nghiêng máy $rounded°',
        metric: angle,
      ),
    ];
  }

  List<CoachHint> _subjectRules(FrameAnalysis frame, Set<String> active) {
    final box = frame.subjectBox;
    if (box == null || frame.subjectConfidence < thresholds.minSubjectConfidence) {
      return const [];
    }
    return [
      ...?_subjectCutRule(box),
      ...?_thirdsRule(box, active),
      ...?_subjectSizeRule(frame, box),
    ];
  }

  /// Subject chạm mép khung → critical (spec FR-S1-3 `subject_cut`).
  List<CoachHint>? _subjectCutRule(SubjectBox box) {
    final cutLeft = math.max(0.0, -box.left);
    final cutRight = math.max(0.0, box.right - 1);
    final cutTop = math.max(0.0, -box.top);
    final cutBottom = math.max(0.0, box.bottom - 1);
    final cutArea = (cutLeft + cutRight) * box.height +
        (cutTop + cutBottom) * box.width;
    if (box.area <= 0 || cutArea / box.area <= thresholds.subjectCutEdgePct) {
      return null;
    }
    return const [
      CoachHint(
        id: 'subject_cut',
        severity: HintSeverity.critical,
        direction: HintDirection.backward,
        message: 'Lùi lại — bị cắt khung',
      ),
    ];
  }

  /// Tâm subject lệch giao điểm thirds gần nhất (spec FR-S1-3 `thirds_offset`).
  List<CoachHint>? _thirdsRule(SubjectBox box, Set<String> active) {
    const intersections = [
      (1 / 3, 1 / 3), (2 / 3, 1 / 3), (1 / 3, 2 / 3), (2 / 3, 2 / 3),
    ];
    var bestDx = double.infinity;
    var bestDy = double.infinity;
    var bestDist = double.infinity;
    for (final (ix, iy) in intersections) {
      final dx = box.centerX - ix;
      final dy = box.centerY - iy;
      final dist = math.sqrt(dx * dx + dy * dy);
      if (dist < bestDist) {
        bestDist = dist;
        bestDx = dx;
        bestDy = dy;
      }
    }
    final threshold = active.contains('thirds_offset')
        ? thresholds.thirdsOffOffset
        : thresholds.thirdsOnOffset;
    if (bestDist <= threshold) return null;

    final horizontal = bestDx.abs() >= bestDy.abs();
    final direction = horizontal
        ? (bestDx > 0 ? HintDirection.left : HintDirection.right)
        : (bestDy > 0 ? HintDirection.up : HintDirection.down);
    const labels = {
      HintDirection.left: 'Di chuyển sang trái',
      HintDirection.right: 'Di chuyển sang phải',
      HintDirection.up: 'Hướng máy lên',
      HintDirection.down: 'Hướng máy xuống',
    };
    return [
      CoachHint(
        id: 'thirds_offset',
        severity: HintSeverity.important,
        direction: direction,
        message: labels[direction]!,
        metric: bestDist,
      ),
    ];
  }

  /// Người trong khung quá nhỏ (spec FR-S1-3 `subject_too_small`).
  List<CoachHint>? _subjectSizeRule(FrameAnalysis frame, SubjectBox box) {
    if (!frame.hasPerson || box.area >= thresholds.subjectMinArea) return null;
    return const [
      CoachHint(
        id: 'subject_too_small',
        severity: HintSeverity.polish,
        direction: HintDirection.forward,
        message: 'Tiến lại gần hơn',
      ),
    ];
  }

  // --- Scoring (Business Rule 5) --------------------------------------------

  /// thirds 40% + horizon 30% + subject size 30%; thiếu dữ liệu thì phần đó
  /// tính điểm trung tính 70 (không thưởng không phạt).
  int _compositionScore(FrameAnalysis frame) {
    const neutral = 70.0;

    double horizonScore = neutral;
    final angle = frame.horizonAngleDeg;
    if (angle != null) {
      horizonScore = (1 - (angle.abs() / 10).clamp(0, 1)) * 100;
    }

    double thirdsScore = neutral;
    double sizeScore = neutral;
    final box = frame.subjectBox;
    if (box != null &&
        frame.subjectConfidence >= thresholds.minSubjectConfidence) {
      var bestDist = double.infinity;
      for (final (ix, iy) in [
        (1 / 3, 1 / 3), (2 / 3, 1 / 3), (1 / 3, 2 / 3), (2 / 3, 2 / 3),
      ]) {
        final dx = box.centerX - ix;
        final dy = box.centerY - iy;
        bestDist = math.min(bestDist, math.sqrt(dx * dx + dy * dy));
      }
      thirdsScore = (1 - (bestDist / 0.4).clamp(0, 1)) * 100;
      // Vùng "đẹp": subject chiếm 15–60% khung.
      sizeScore = box.area >= 0.15 && box.area <= 0.60
          ? 100
          : box.area < 0.15
              ? (box.area / 0.15) * 100
              : (1 - ((box.area - 0.60) / 0.40).clamp(0, 1)) * 100;
    }

    return (thirdsScore * 0.4 + horizonScore * 0.3 + sizeScore * 0.3)
        .round()
        .clamp(0, 100);
  }
}
