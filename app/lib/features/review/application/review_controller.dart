/// `reviewControllerProvider` (spec-sprint-3 FR-S3-3 + "State Management") —
/// state machine idle → uploading → queued → polling → done/failed.
///
/// Flow (spec): resize ≤1568px (TODO — cần package `image`, ngoài scope run
/// này) → upload-url → PUT file → enqueue review → poll `GET review` mỗi 2s
/// tối đa 90s → done: persist Drift (`kind:'cloud'`) + expose result; 402 →
/// failed('Hết lượt review...'); timeout → stillProcessing (EC-S3-13).
library;

import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../history/data/analyses_repository.dart';
import '../../history/data/photos_repository.dart';
import '../data/review_repository.dart';
import '../domain/review_result.dart';
import 'review_state.dart';

const _pollInterval = Duration(seconds: 2);
const _pollTimeout = Duration(seconds: 90);

class ReviewController extends FamilyAsyncNotifier<ReviewState, String> {
  @override
  Future<ReviewState> build(String arg) async {
    return const ReviewState.idle();
  }

  String get _photoId => arg;

  Future<void> startReview() async {
    state = const AsyncData(ReviewState.uploading());
    try {
      final photosRepo = ref.read(photosRepositoryProvider);
      final photo = await photosRepo.getById(_photoId);
      if (photo == null) {
        state = const AsyncData(ReviewState.failed('Không tìm thấy ảnh'));
        return;
      }

      final reviewRepo = ref.read(reviewRepositoryProvider);
      const contentType = 'image/jpeg';

      // TODO: resize <=1568px cạnh dài, JPEG q85 trong isolate (cần package
      // `image`, ngoài scope run này — spec FR-S3-2). Hiện đọc bytes gốc.
      final file = File(photo.filePath);
      if (!file.existsSync()) {
        state = const AsyncData(ReviewState.failed('Không tìm thấy file ảnh'));
        return;
      }

      final uploadUrlResult = await reviewRepo.requestUploadUrl(
        photoId: _photoId,
        contentType: contentType,
      );
      await reviewRepo.uploadFile(
        uploadUrl: uploadUrlResult.uploadUrl,
        file: file,
        contentType: contentType,
      );

      state = const AsyncData(ReviewState.queued());
      await reviewRepo.enqueueReview(_photoId);

      state = const AsyncData(ReviewState.polling());
      await _pollUntilDone(reviewRepo);
    } on DioException catch (e) {
      state = AsyncData(ReviewState.failed(_messageFor(e)));
    } catch (_) {
      state = const AsyncData(
        ReviewState.failed('Có lỗi xảy ra — thử lại sau'),
      );
    }
  }

  Future<void> _pollUntilDone(ReviewRepository reviewRepo) async {
    final deadline = DateTime.now().add(_pollTimeout);
    while (DateTime.now().isBefore(deadline)) {
      final result = await reviewRepo.getReview(_photoId);
      if (result.status == 'DONE') {
        await _persistResult(result);
        state = AsyncData(ReviewState.done(result));
        return;
      }
      if (result.status == 'FAILED') {
        state = const AsyncData(
          ReviewState.failed('Thử lại sau'),
        );
        return;
      }
      await Future<void>.delayed(_pollInterval);
    }
    // EC-S3-13: quá 90s chưa done — dừng poll, không coi là lỗi.
    state = const AsyncData(ReviewState.stillProcessing());
  }

  /// Lưu kết quả cloud review vào Drift `analyses` hiện có — KHÔNG đổi
  /// schema (spec FR-S3-3: `kind:'cloud', provider:'claude'|'gemini'`).
  Future<void> _persistResult(ReviewResult result) async {
    final analysesRepo = ref.read(analysesRepositoryProvider);
    await analysesRepo.insertAnalysis(
      photoId: _photoId,
      result: _resultToJson(result),
      createdAt: DateTime.now(),
      kind: 'cloud',
      provider: result.provider ?? 'unknown',
    );
  }

  String _resultToJson(ReviewResult result) {
    final scores = result.scores;
    return '{'
        '"explanation":${_jsonString(result.explanation ?? '')},'
        '"suggestions":${_jsonStringList(result.suggestions)},'
        '"scores":{'
        '"composition":${scores?.composition ?? 0},'
        '"lighting":${scores?.lighting ?? 0},'
        '"focus":${scores?.focus ?? 0},'
        '"background":${scores?.background ?? 0}'
        '}'
        '}';
  }

  String _jsonString(String value) {
    final escaped = value
        .replaceAll(r'\', r'\\')
        .replaceAll('"', r'\"')
        .replaceAll('\n', r'\n');
    return '"$escaped"';
  }

  String _jsonStringList(List<String> values) {
    return '[${values.map(_jsonString).join(',')}]';
  }

  String _messageFor(DioException e) {
    final statusCode = e.response?.statusCode;
    if (statusCode == 402) return 'Hết lượt review — nâng cấp';
    if (statusCode == 422) return 'Ảnh chưa upload xong — thử lại';
    if (statusCode == 409) return 'Ảnh này đang được review';
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError) {
      return 'Cần mạng để review';
    }
    return 'Thử lại sau';
  }

  void reset() {
    state = const AsyncData(ReviewState.idle());
  }
}

final reviewControllerProvider =
    AsyncNotifierProvider.family<ReviewController, ReviewState, String>(
  ReviewController.new,
);
