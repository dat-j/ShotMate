/// Model kết quả review AI (spec-sprint-3 API: `GET /photos/:id/review`
/// response shape).
library;

import 'package:freezed_annotation/freezed_annotation.dart';

part 'review_result.freezed.dart';
part 'review_result.g.dart';

@freezed
class ReviewScores with _$ReviewScores {
  const factory ReviewScores({
    required int composition,
    required int lighting,
    required int focus,
    required int background,
  }) = _ReviewScores;

  factory ReviewScores.fromJson(Map<String, Object?> json) =>
      _$ReviewScoresFromJson(json);
}

@freezed
class ReviewResult with _$ReviewResult {
  const factory ReviewResult({
    required String reviewId,
    required String status, // QUEUED | PROCESSING | DONE | FAILED
    String? provider, // 'claude' | 'gemini' — null khi chưa done
    ReviewScores? scores,
    String? explanation,
    @Default(<String>[]) List<String> suggestions,
    required String createdAt,
  }) = _ReviewResult;

  factory ReviewResult.fromJson(Map<String, Object?> json) =>
      _$ReviewResultFromJson(json);
}
