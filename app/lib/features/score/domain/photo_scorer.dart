/// Photo Score v0 — 4 chiều điểm sau khi chụp (spec-sprint-1 FR-S1-5).
///
/// Pure function, không I/O, không phụ thuộc Flutter — cùng input luôn cho
/// cùng output (giống rule engine, ADR-0003 áp dụng tinh thần deterministic
/// tương tự cho scoring dù đây không phải realtime guidance). Composition
/// KHÔNG được tính lại ở đây: nó đến từ `CoachState.compositionScore` của
/// rule engine trên analysis frame gần capture nhất (spec FR-S1-5), nên
/// [PhotoScorer] chỉ nhận giá trị đã tính sẵn làm input.
library;

import 'dart:math' as math;

import '../../coach/domain/frame_analysis.dart';

/// Ngưỡng khởi điểm cho Lighting/Focus/Background — giá trị Sprint-1, sẽ
/// tuning thực địa (theo đúng convention của `CoachThresholds`, giữ tất cả
/// hằng số ở một chỗ — spec Open Questions).
class PhotoScoreThresholds {
  const PhotoScoreThresholds({
    // Lighting: dải meanLuma [0,255] được coi là "well-exposed". Midtone lý
    // tưởng cho ảnh chân dung/đời thường rơi vào khoảng 110–160 (kinh nghiệm
    // nhiếp ảnh phổ thông: 18% gray ~ 118 nhưng ảnh thực tế "đẹp mắt" thường
    // sáng hơn một chút). Ngoài dải này, điểm giảm tuyến tính tới 0 tại biên.
    this.lumaTargetLow = 110.0,
    this.lumaTargetHigh = 160.0,
    this.lumaFalloffRange = 90.0,
    // Clip highlight/shadow là % pixel — phạt tuyến tính, "unusable" ở 15%.
    this.clipPenaltyCeiling = 0.15,

    // Focus: sharpness = Laplacian variance (native). Ngưỡng kinh nghiệm phổ
    // biến trong xử lý ảnh: variance < 10 → mờ rõ rệt (blurDetect classic),
    // >= 100 → nét tốt. Dùng log-scale vì variance có thể lớn tuỳ scene
    // (nhiều cạnh → variance rất cao), log giúp nén dải giá trị hợp lý hơn
    // linear thô. Đây là điểm khởi đầu Sprint-1, cần tuning thực địa giống
    // CoachThresholds.
    this.sharpnessBlurCeiling = 10.0,
    this.sharpnessSharpFloor = 100.0,

    // Background: edge density ngoài subjectBox, [0,1]. Nền càng ít cạnh
    // càng "sạch". >= 0.5 coi như rất bận (busy).
    this.backgroundBusyCeiling = 0.5,
  });

  final double lumaTargetLow;
  final double lumaTargetHigh;
  final double lumaFalloffRange;
  final double clipPenaltyCeiling;

  final double sharpnessBlurCeiling;
  final double sharpnessSharpFloor;

  final double backgroundBusyCeiling;

  static const defaults = PhotoScoreThresholds();
}

/// Kết quả 4 chiều điểm, mỗi chiều ∈ [0,100] (spec Data Validation table).
class PhotoScore {
  const PhotoScore({
    required this.composition,
    required this.lighting,
    required this.focus,
    required this.background,
  });

  final int composition;
  final int lighting;
  final int focus;
  final int background;
}

class PhotoScorer {
  const PhotoScorer({this.thresholds = PhotoScoreThresholds.defaults});

  final PhotoScoreThresholds thresholds;

  /// [compositionScore]: điểm đã tính sẵn từ `CoachRuleEngine` trên analysis
  /// frame gần capture nhất — KHÔNG tính lại composition ở đây.
  /// [exposure]: metrics từ frame gần capture nhất, null → điểm trung tính.
  /// [sharpnessVariance]: Laplacian variance, tính native ngay sau capture.
  /// [backgroundEdgeDensity]: mật độ cạnh ngoài subjectBox ∈ [0,1], native.
  PhotoScore score({
    required int compositionScore,
    ExposureInfo? exposure,
    required double sharpnessVariance,
    required double backgroundEdgeDensity,
  }) {
    return PhotoScore(
      composition: compositionScore.clamp(0, 100),
      lighting: _lightingScore(exposure),
      focus: _focusScore(sharpnessVariance),
      background: _backgroundScore(backgroundEdgeDensity),
    );
  }

  // --- Lighting --------------------------------------------------------------

  /// Thưởng meanLuma trong dải "well-exposed" [lumaTargetLow, lumaTargetHigh],
  /// giảm tuyến tính khi lệch ra ngoài; phạt thêm theo % pixel bị clip
  /// highlight/shadow (mất chi tiết không phục hồi được).
  int _lightingScore(ExposureInfo? exposure) {
    if (exposure == null) return 70; // thiếu dữ liệu → trung tính

    final luma = exposure.meanLuma.clamp(0, 255);
    double exposureScore;
    if (luma >= thresholds.lumaTargetLow && luma <= thresholds.lumaTargetHigh) {
      exposureScore = 100;
    } else {
      final distance = luma < thresholds.lumaTargetLow
          ? thresholds.lumaTargetLow - luma
          : luma - thresholds.lumaTargetHigh;
      exposureScore =
          (1 - (distance / thresholds.lumaFalloffRange).clamp(0, 1)) * 100;
    }

    final highlightPenalty =
        (exposure.clippedHighlightsPct / thresholds.clipPenaltyCeiling)
            .clamp(0, 1) *
        100;
    final shadowPenalty =
        (exposure.clippedShadowsPct / thresholds.clipPenaltyCeiling)
            .clamp(0, 1) *
        100;
    final clipPenalty = math.max(highlightPenalty, shadowPenalty);

    return (exposureScore - clipPenalty).round().clamp(0, 100);
  }

  // --- Focus -------------------------------------------------------------

  /// Map Laplacian variance → 0-100 dùng log-scale giữa ngưỡng "mờ" và
  /// "nét" (xem comment ở [PhotoScoreThresholds]).
  int _focusScore(double sharpnessVariance) {
    final variance = math.max(0.0, sharpnessVariance);
    if (variance <= thresholds.sharpnessBlurCeiling) return 0;
    if (variance >= thresholds.sharpnessSharpFloor) return 100;

    final logBlur = math.log(thresholds.sharpnessBlurCeiling);
    final logSharp = math.log(thresholds.sharpnessSharpFloor);
    final logVariance = math.log(variance);
    final ratio = (logVariance - logBlur) / (logSharp - logBlur);
    return (ratio.clamp(0, 1) * 100).round();
  }

  // --- Background ----------------------------------------------------------

  /// Edge density ngoài subjectBox càng thấp → nền càng "sạch" → điểm càng
  /// cao. Đảo ngược tuyến tính trong [0, backgroundBusyCeiling].
  int _backgroundScore(double backgroundEdgeDensity) {
    final density = backgroundEdgeDensity.clamp(0, 1);
    final normalized = (density / thresholds.backgroundBusyCeiling).clamp(0, 1);
    return ((1 - normalized) * 100).round().clamp(0, 100);
  }
}
