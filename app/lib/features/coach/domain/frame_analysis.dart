/// Contract dữ liệu từ Native Inference Module → Dart (ADR-0001).
///
/// Native side (Kotlin/Swift) serialize đúng schema này qua EventChannel
/// `shotmate/frame_analysis`. Payload ≤ 2KB, KHÔNG BAO GIỜ chứa pixel data
/// (spec-sprint-1 Business Rule 3). Đổi cấu trúc → tăng [FrameAnalysis.supportedSchemaVersion]
/// và cập nhật cả hai native module.
///
/// Viết tay (không freezed) để rule engine chạy được không cần build_runner;
/// có thể migrate sang freezed khi codegen đã nằm trong workflow.
library;

/// Bounding box normalized [0,1] theo khung hình.
class SubjectBox {
  const SubjectBox({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final double left;
  final double top;
  final double width;
  final double height;

  double get right => left + width;
  double get bottom => top + height;
  double get area => width * height;
  double get centerX => left + width / 2;
  double get centerY => top + height / 2;

  factory SubjectBox.fromJson(Map<String, Object?> json) => SubjectBox(
        left: (json['left']! as num).toDouble(),
        top: (json['top']! as num).toDouble(),
        width: (json['width']! as num).toDouble(),
        height: (json['height']! as num).toDouble(),
      );

  Map<String, Object?> toJson() =>
      {'left': left, 'top': top, 'width': width, 'height': height};
}

class ExposureInfo {
  const ExposureInfo({
    required this.meanLuma,
    required this.clippedHighlightsPct,
    required this.clippedShadowsPct,
  });

  /// [0,255]
  final double meanLuma;
  final double clippedHighlightsPct;
  final double clippedShadowsPct;

  factory ExposureInfo.fromJson(Map<String, Object?> json) => ExposureInfo(
        meanLuma: (json['meanLuma']! as num).toDouble(),
        clippedHighlightsPct:
            (json['clippedHighlightsPct']! as num).toDouble(),
        clippedShadowsPct: (json['clippedShadowsPct']! as num).toDouble(),
      );
}

class FrameAnalysis {
  const FrameAnalysis({
    required this.schemaVersion,
    required this.timestampMs,
    this.horizonAngleDeg,
    this.subjectBox,
    this.subjectConfidence = 0,
    this.hasPerson = false,
    this.poseLandmarks,
    this.exposure,
    this.inferenceLatencyMs = const {},
  });

  static const supportedSchemaVersion = 1;

  final int schemaVersion;
  final int timestampMs;

  /// Độ nghiêng đường chân trời, độ, [-45, 45]. Dương = máy nghiêng phải.
  final double? horizonAngleDeg;
  final SubjectBox? subjectBox;

  /// [0,1] — dưới ngưỡng tin cậy thì rule engine bỏ qua subject.
  final double subjectConfidence;
  final bool hasPerson;

  /// 33 điểm MediaPipe, mỗi điểm [x, y] normalized [0,1]. Null nếu không có người.
  final List<List<double>>? poseLandmarks;
  final ExposureInfo? exposure;

  /// Latency mỗi detector (ms), key: 'pose' | 'composition' | ... — do native
  /// đo (FR-S1-7). Rỗng nếu native không gửi. Dùng feed PerfTracker cho
  /// benchmark gate; không ảnh hưởng guidance.
  final Map<String, int> inferenceLatencyMs;

  /// Parse payload từ EventChannel. Trả null nếu schema không khớp
  /// hoặc dữ liệu ngoài miền hợp lệ (spec: silent drop + log phía caller).
  static FrameAnalysis? tryParse(Map<String, Object?> json) {
    if (json['schemaVersion'] != supportedSchemaVersion) return null;
    final landmarks = (json['poseLandmarks'] as List<Object?>?)
        ?.map((p) =>
            (p! as List<Object?>).map((v) => (v! as num).toDouble()).toList())
        .toList();
    if (landmarks != null &&
        (landmarks.length != 33 ||
            landmarks.any(
                (p) => p.any((v) => v < 0 || v > 1)))) {
      return null;
    }
    final rawAngle = (json['horizonAngleDeg'] as num?)?.toDouble();
    final latency = (json['inferenceLatencyMs'] as Map<Object?, Object?>?)?.map(
          (k, v) => MapEntry(k! as String, (v! as num).toInt()),
        ) ??
        const <String, int>{};
    return FrameAnalysis(
      schemaVersion: json['schemaVersion']! as int,
      timestampMs: json['timestampMs']! as int,
      horizonAngleDeg: rawAngle?.clamp(-45, 45),
      inferenceLatencyMs: latency,
      subjectBox: json['subjectBox'] == null
          ? null
          : SubjectBox.fromJson(json['subjectBox']! as Map<String, Object?>),
      subjectConfidence:
          (json['subjectConfidence'] as num?)?.toDouble() ?? 0,
      hasPerson: json['hasPerson'] as bool? ?? false,
      poseLandmarks: landmarks,
      exposure: json['exposure'] == null
          ? null
          : ExposureInfo.fromJson(json['exposure']! as Map<String, Object?>),
    );
  }
}
