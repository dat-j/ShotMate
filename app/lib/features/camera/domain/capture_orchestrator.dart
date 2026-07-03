/// Orchestration "capture → score → persist" (spec-sprint-1 FR-S1-5, EC-5,
/// EC-7) — tách khỏi widget để test được với fake repo, không cần camera
/// plugin thật (camera plugin không mock được có ý nghĩa, spec builder note).
///
/// Luồng:
/// 1. Lưu photo record (luôn thực hiện, kể cả hết quota — spec: "vẫn chụp
///    được ảnh, không hiển thị score").
/// 2. Ghi analysis record (snapshot FrameAnalysis + input scorer dạng JSON).
/// 3. Kiểm tra credit TRƯỚC khi tính score (Business Rule 4 / EC-5) — hết
///    quota → bỏ qua bước insertScore, KHÔNG gọi recordScore.
/// 4. Nếu còn quota: tính [PhotoScorer.score], lưu Score, gọi recordScore().
///
/// Debounce/concurrent-capture (EC-7) là trách nhiệm của caller (widget) —
/// orchestrator chỉ đảm bảo 1 lần gọi [capture] luôn tạo đúng 1 photo record,
/// không tự lặp lại.
library;

import 'dart:convert';

import '../../coach/domain/frame_analysis.dart';
import '../../history/data/analyses_repository.dart';
import '../../history/data/credit_repository.dart';
import '../../history/data/photos_repository.dart';
import '../../score/data/scores_repository.dart';
import '../../score/domain/photo_scorer.dart';

/// TODO(sprint-1-native): Focus (Laplacian variance) và Background (edge
/// density ngoài subjectBox) đúng ra phải tính ở native ngay sau capture
/// (spec FR-S1-5) — nhưng native runner project (app/android, app/ios) chưa
/// tồn tại trong repo này (xem app/android/NATIVE_MODULE.md, "sẽ được sinh
/// bởi `flutter create`"). Dùng giá trị placeholder trung tính cho tới khi
/// native module Sprint 1 sẵn sàng, để Sprint 1 Dart-layer (repo writes,
/// credit check, navigation) có thể build/test end-to-end ngay bây giờ.
const placeholderSharpnessVariance = 50.0;
const placeholderBackgroundEdgeDensity = 0.3;

/// Kết quả 1 lần capture — đủ thông tin để widget navigate/hiển thị.
class CaptureResult {
  const CaptureResult({required this.photoId, required this.scored});

  final String photoId;

  /// false khi hết quota (EC-5) — score bị bỏ qua, ảnh vẫn lưu.
  final bool scored;
}

/// Phụ thuộc trừu tượng vào 4 repository — inject để test bằng fake.
class CaptureOrchestrator {
  const CaptureOrchestrator({
    required this.photosRepository,
    required this.analysesRepository,
    required this.scoresRepository,
    required this.creditRepository,
    this.scorer = const PhotoScorer(),
  });

  final PhotosRepository photosRepository;
  final AnalysesRepository analysesRepository;
  final ScoresRepository scoresRepository;
  final CreditRepository creditRepository;
  final PhotoScorer scorer;

  /// Thực hiện toàn bộ luồng persist + score cho 1 ảnh vừa chụp.
  ///
  /// [filePath]: đường dẫn ảnh đã lưu app-private (widget lo phần chụp/lưu
  /// file, orchestrator không biết về `camera` plugin).
  /// [captureMeta]: JSON string (zoom, tilt, hints_shown — spec Database
  /// Changes) — caller serialize sẵn.
  /// [analysis]: FrameAnalysis gần nhất trước khi bấm chụp (từ
  /// `frameAnalysisStreamProvider`), null nếu chưa có frame nào (vd chụp
  /// ngay khi mở app — vẫn phải cho chụp, dùng giá trị trung tính).
  /// [compositionScore]: từ `CoachState.compositionScore` (rule engine) tại
  /// thời điểm chụp — spec: "KHÔNG tính lại composition ở đây".
  Future<CaptureResult> capture({
    required String filePath,
    required String captureMeta,
    required int compositionScore,
    FrameAnalysis? analysis,
    DateTime? now,
  }) async {
    final capturedAt = now ?? DateTime.now();

    final photoId = await photosRepository.insertPhoto(
      filePath: filePath,
      captureMeta: captureMeta,
      takenAt: capturedAt,
    );

    final canScore = await creditRepository.canScore(capturedAt);

    PhotoScore? photoScore;
    if (canScore) {
      photoScore = scorer.score(
        compositionScore: compositionScore,
        exposure: analysis?.exposure,
        sharpnessVariance: placeholderSharpnessVariance,
        backgroundEdgeDensity: placeholderBackgroundEdgeDensity,
      );
    }

    final analysisId = await analysesRepository.insertAnalysis(
      photoId: photoId,
      result: jsonEncode(_analysisSnapshot(analysis, compositionScore, photoScore)),
      createdAt: capturedAt,
    );

    if (photoScore == null) {
      return CaptureResult(photoId: photoId, scored: false);
    }

    await scoresRepository.insertScore(
      analysisId: analysisId,
      composition: photoScore.composition,
      lighting: photoScore.lighting,
      focus: photoScore.focus,
      background: photoScore.background,
    );
    await creditRepository.recordScore(capturedAt);

    return CaptureResult(photoId: photoId, scored: true);
  }

  Map<String, Object?> _analysisSnapshot(
    FrameAnalysis? analysis,
    int compositionScore,
    PhotoScore? score,
  ) {
    return {
      'frameAnalysis': analysis == null
          ? null
          : {
              'schemaVersion': analysis.schemaVersion,
              'timestampMs': analysis.timestampMs,
              'horizonAngleDeg': analysis.horizonAngleDeg,
              'hasPerson': analysis.hasPerson,
              'subjectConfidence': analysis.subjectConfidence,
              'exposure': analysis.exposure == null
                  ? null
                  : {
                      'meanLuma': analysis.exposure!.meanLuma,
                      'clippedHighlightsPct':
                          analysis.exposure!.clippedHighlightsPct,
                      'clippedShadowsPct': analysis.exposure!.clippedShadowsPct,
                    },
            },
      'compositionScoreInput': compositionScore,
      'score': score == null
          ? null
          : {
              'composition': score.composition,
              'lighting': score.lighting,
              'focus': score.focus,
              'background': score.background,
            },
    };
  }
}
