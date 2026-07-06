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

/// Phân loại scene v1 (spec-sprint-2 FR-S2-2). `unknown` = chưa rõ / khởi động.
enum SceneType {
  landscape,
  portrait,
  food,
  unknown;

  /// Parse từ string native, coerce về [unknown] nếu không hợp lệ
  /// (spec-sprint-2 Data Validation).
  static SceneType fromName(Object? raw) {
    if (raw is! String) return SceneType.unknown;
    for (final v in SceneType.values) {
      if (v.name == raw) return v;
    }
    return SceneType.unknown;
  }
}

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
    this.sceneType = SceneType.unknown,
    this.sceneConfidence = 0,
    this.smilingProbability,
    this.pitchDeg,
    this.zoomRatio = 1,
    this.verticalFovDeg,
    this.throttled = false,
  });

  static const supportedSchemaVersion = 2;

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

  // --- schemaVersion 2 (spec-sprint-2 FR-S2-8) ---

  /// Scene raw mỗi frame (chưa qua Rule 6 ổn định 3 mẫu — đó là việc của Dart).
  final SceneType sceneType;

  /// [0,1] độ tin cậy scene classifier.
  final double sceneConfidence;

  /// [0,1] xác suất cười (ML Kit face). Null nếu không có mặt / không đo.
  final double? smilingProbability;

  /// Góc chúc/ngửa máy, độ, [-90,90]. 0 = dựng đứng vuông mặt đất, dương = ngửa.
  final double? pitchDeg;

  /// Zoom hiện tại (bội số quang/số). Mặc định 1x.
  final double zoomRatio;

  /// FOV dọc (độ) đọc từ CameraCharacteristics — dùng ước lượng khoảng cách.
  /// Null nếu thiết bị không cung cấp (rule distance tự tắt — FR-S2-4).
  final double? verticalFovDeg;

  /// Thiết bị đang throttle vì nhiệt (EC-4) — UI hiện icon tiết kiệm.
  final bool throttled;

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
    final smile = (json['smilingProbability'] as num?)?.toDouble();
    final pitch = (json['pitchDeg'] as num?)?.toDouble();
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
      sceneType: SceneType.fromName(json['sceneType']),
      sceneConfidence:
          ((json['sceneConfidence'] as num?)?.toDouble() ?? 0).clamp(0, 1),
      smilingProbability: smile?.clamp(0, 1),
      pitchDeg: pitch?.clamp(-90, 90),
      zoomRatio: ((json['zoomRatio'] as num?)?.toDouble() ?? 1).clamp(0.1, 20),
      verticalFovDeg: (json['verticalFovDeg'] as num?)?.toDouble(),
      throttled: json['throttled'] as bool? ?? false,
    );
  }
}
