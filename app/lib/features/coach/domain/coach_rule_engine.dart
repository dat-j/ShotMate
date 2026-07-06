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
    // --- Sprint 2 (spec-sprint-2 Business Rules 1–4) ---
    this.poseMinConfidence = 0.7,
    this.chinOnPct = 0.08,
    this.chinOffPct = 0.04,
    this.smileOnProb = 0.3,
    this.smileOffProb = 0.5,
    this.tooCloseOnPct = 0.65,
    this.tooCloseOffPct = 0.55,
    this.tooFarOnPct = 0.25,
    this.tooFarOffPct = 0.32,
    this.angleOnDeg = 10.0,
    this.angleOffDeg = 5.0,
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

  /// Pose hint chỉ chạy khi subjectConfidence ≥ ngưỡng này (BR-1).
  final double poseMinConfidence;

  /// raise_chin: mũi thấp hơn trung điểm vai > chinOnPct chiều cao khung.
  final double chinOnPct;
  final double chinOffPct;
  final double smileOnProb;
  final double smileOffProb;

  /// Distance: box height so với chiều cao khung (BR-3).
  final double tooCloseOnPct;
  final double tooCloseOffPct;
  final double tooFarOnPct;
  final double tooFarOffPct;

  /// Angle: lệch dải pitch theo scene (BR-4).
  final double angleOnDeg;
  final double angleOffDeg;

  static const defaults = CoachThresholds();
}

class CoachRuleEngine {
  const CoachRuleEngine({this.thresholds = CoachThresholds.defaults});

  final CoachThresholds thresholds;

  /// [activeHintIds]: các hint đang hiển thị từ lần đánh giá trước —
  /// dùng ngưỡng OFF thay vì ON cho các rule này (hysteresis).
  /// [stableScene]: scene đã qua Rule 6 (ổn định 3 mẫu) từ provider — engine
  /// không tự làm ổn định (giữ pure). Null/unknown → rule phụ thuộc scene tắt.
  CoachState evaluate(
    FrameAnalysis frame, {
    Set<String> activeHintIds = const {},
    SceneType stableScene = SceneType.unknown,
  }) {
    final hints = <CoachHint>[
      ...?_horizonRule(frame, activeHintIds),
      ..._subjectRules(frame, activeHintIds),
      ..._poseRules(frame, activeHintIds),
      ...?_distanceRule(frame, activeHintIds),
      ...?_angleRule(frame, activeHintIds, stableScene),
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

  // --- Sprint 2 rules -------------------------------------------------------

  /// Pose hints (spec-sprint-2 FR-S2-1, BR-1/2). Chỉ chạy khi chắc chắn có
  /// người (subjectConfidence ≥ poseMinConfidence) và có landmark.
  List<CoachHint> _poseRules(FrameAnalysis frame, Set<String> active) {
    if (!frame.hasPerson ||
        frame.subjectConfidence < thresholds.poseMinConfidence) {
      return const [];
    }
    return [
      ...?_raiseChinRule(frame, active),
      ...?_smileRule(frame, active),
    ];
  }

  /// Mũi (landmark 0) thấp hơn trung điểm hai vai (11, 12) > ngưỡng → nâng cằm.
  /// Trục y ảnh: xuống dưới = y lớn hơn, nên "mũi thấp hơn vai" = nose.y > shoulder.y.
  List<CoachHint>? _raiseChinRule(FrameAnalysis frame, Set<String> active) {
    final lm = frame.poseLandmarks;
    if (lm == null || lm.length != 33) return null;
    final noseY = lm[0][1];
    final shoulderMidY = (lm[11][1] + lm[12][1]) / 2;
    final drop = noseY - shoulderMidY;
    final threshold =
        active.contains('raise_chin') ? thresholds.chinOffPct : thresholds.chinOnPct;
    if (drop <= threshold) return null;
    return const [
      CoachHint(
        id: 'raise_chin',
        severity: HintSeverity.polish,
        direction: HintDirection.up,
        message: 'Nâng cằm lên',
      ),
    ];
  }

  /// smilingProbability thấp → gợi ý cười (spec BR-2). Việc "liên tục 2s" là
  /// trách nhiệm của caller (stateful, giống hysteresis) — engine chỉ so ngưỡng
  /// tức thời với hysteresis ON/OFF.
  List<CoachHint>? _smileRule(FrameAnalysis frame, Set<String> active) {
    final prob = frame.smilingProbability;
    if (prob == null) return null;
    final threshold =
        active.contains('smile') ? thresholds.smileOffProb : thresholds.smileOnProb;
    if (prob >= threshold) return null;
    return const [
      CoachHint(
        id: 'smile',
        severity: HintSeverity.polish,
        direction: HintDirection.none,
        message: 'Cười lên nào 😊',
      ),
    ];
  }

  /// Distance guide (spec-sprint-2 FR-S2-4, BR-3). Cần person + FOV để ước
  /// lượng cm; thiếu FOV → vẫn cảnh báo gần/xa nhưng không kèm số cm.
  List<CoachHint>? _distanceRule(FrameAnalysis frame, Set<String> active) {
    final box = frame.subjectBox;
    if (box == null ||
        !frame.hasPerson ||
        frame.subjectConfidence < thresholds.poseMinConfidence) {
      return null;
    }
    final h = box.height;

    final tooCloseThreshold = active.contains('too_close')
        ? thresholds.tooCloseOffPct
        : thresholds.tooCloseOnPct;
    if (h > tooCloseThreshold) {
      return [
        CoachHint(
          id: 'too_close',
          severity: HintSeverity.important,
          direction: HintDirection.backward,
          message: _distanceMessage(frame, box, moveBack: true),
          metric: h,
        ),
      ];
    }

    final tooFarThreshold = active.contains('too_far')
        ? thresholds.tooFarOffPct
        : thresholds.tooFarOnPct;
    if (h < tooFarThreshold) {
      return [
        CoachHint(
          id: 'too_far',
          severity: HintSeverity.polish,
          direction: HintDirection.forward,
          message: _distanceMessage(frame, box, moveBack: false),
          metric: h,
        ),
      ];
    }
    return null;
  }

  /// "Lùi/Tiến ~Ncm" — ước lượng từ FOV + giả định người cao ~1.7m. Không có
  /// FOV thì bỏ phần cm (copy dùng "~", sai số ±30% — hướng dẫn, không đo).
  String _distanceMessage(FrameAnalysis frame, SubjectBox box,
      {required bool moveBack}) {
    final verb = moveBack ? 'Lùi' : 'Tiến';
    final fov = frame.verticalFovDeg;
    if (fov == null || box.height <= 0) return '$verb lại một chút';
    const personHeightM = 1.7;
    // Khoảng cách hiện tại ≈ (personHeight/2) / tan((fov/2)*boxHeightFraction)
    final halfAngle = (fov / 2) * box.height * (math.pi / 180);
    final currentM = halfAngle > 0
        ? (personHeightM / 2) / math.tan(halfAngle)
        : 0.0;
    // Target: box height ~45% khung (giữa dải đẹp)
    const targetFraction = 0.45;
    final targetHalfAngle = (fov / 2) * targetFraction * (math.pi / 180);
    final targetM = targetHalfAngle > 0
        ? (personHeightM / 2) / math.tan(targetHalfAngle)
        : currentM;
    final deltaCm = ((targetM - currentM).abs() * 100 / 10).round() * 10;
    if (deltaCm <= 0) return '$verb lại một chút';
    return '$verb ~${deltaCm}cm';
  }

  /// Angle guide (spec-sprint-2 FR-S2-5, BR-4). Chỉ chạy khi scene ổn định là
  /// portrait/food (landscape để horizon rule lo).
  List<CoachHint>? _angleRule(
      FrameAnalysis frame, Set<String> active, SceneType scene) {
    final pitch = frame.pitchDeg;
    if (pitch == null) return null;

    final threshold =
        active.contains('tilt_angle') ? thresholds.angleOffDeg : thresholds.angleOnDeg;

    double? deviation; // dương = cần ngẩng lên, âm = cần cúi xuống
    switch (scene) {
      case SceneType.portrait:
        // Dải tốt ±0° (ngang tầm mắt); lệch = -pitch (pitch>0 ngửa → cúi xuống)
        if (pitch.abs() > threshold) deviation = -pitch;
      case SceneType.food:
        // Dải tốt: 45° hoặc 90° (top-down). Chọn dải gần nhất.
        final to45 = 45 - pitch;
        final to90 = 90 - pitch;
        final nearest = to45.abs() <= to90.abs() ? to45 : to90;
        if (nearest.abs() > threshold) deviation = nearest;
      case SceneType.landscape:
      case SceneType.unknown:
        return null;
    }
    if (deviation == null) return null;
    final rounded = deviation.abs().round();
    return [
      CoachHint(
        id: 'tilt_angle',
        severity: HintSeverity.polish,
        direction: deviation > 0 ? HintDirection.up : HintDirection.down,
        message: deviation > 0 ? 'Ngẩng máy ~$rounded°' : 'Cúi máy ~$rounded°',
        metric: pitch,
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
