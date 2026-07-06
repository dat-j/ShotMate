/// State machine cho `reviewControllerProvider` (spec-sprint-3 FR-S3-3):
/// idle → uploading → queued → polling → done(result)/failed(reason).
library;

import 'package:freezed_annotation/freezed_annotation.dart';

import '../domain/review_result.dart';

part 'review_state.freezed.dart';

@freezed
sealed class ReviewState with _$ReviewState {
  const factory ReviewState.idle() = ReviewIdle;
  const factory ReviewState.uploading() = ReviewUploading;
  const factory ReviewState.queued() = ReviewQueued;
  const factory ReviewState.polling() = ReviewPolling;
  const factory ReviewState.done(ReviewResult result) = ReviewDone;
  const factory ReviewState.failed(String reason) = ReviewFailed;
  // EC-S3-13: quá 90s chưa done — dừng poll, không phải lỗi thật, job vẫn
  // chạy server-side, kết quả sẽ có trong History lần sau.
  const factory ReviewState.stillProcessing() = ReviewStillProcessing;
}
