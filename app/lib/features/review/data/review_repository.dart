/// Dio calls cho cloud review pipeline (spec-sprint-3 FR-S3-2, FR-S3-3).
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/review_result.dart';

class UploadUrlResult {
  const UploadUrlResult({
    required this.uploadUrl,
    required this.storagePath,
    required this.expiresAt,
  });

  factory UploadUrlResult.fromJson(Map<String, Object?> json) {
    return UploadUrlResult(
      uploadUrl: json['uploadUrl']! as String,
      storagePath: json['storagePath']! as String,
      expiresAt: json['expiresAt']! as String,
    );
  }

  final String uploadUrl;
  final String storagePath;
  final String expiresAt;
}

class EnqueueReviewResult {
  const EnqueueReviewResult({
    required this.reviewId,
    required this.status,
    required this.creditsRemaining,
  });

  factory EnqueueReviewResult.fromJson(Map<String, Object?> json) {
    return EnqueueReviewResult(
      reviewId: json['reviewId']! as String,
      status: json['status']! as String,
      creditsRemaining: json['creditsRemaining']! as int,
    );
  }

  final String reviewId;
  final String status;
  final int creditsRemaining;
}

class ReviewRepository {
  ReviewRepository(this._dio);

  final Dio _dio;

  /// `POST /photos/upload-url` — signed URL TTL 15 phút (FR-S3-2).
  Future<UploadUrlResult> requestUploadUrl({
    required String photoId,
    required String contentType,
  }) async {
    final response = await _dio.post<Map<String, Object?>>(
      '/photos/upload-url',
      data: {'photoId': photoId, 'contentType': contentType},
    );
    return UploadUrlResult.fromJson(response.data!);
  }

  /// PUT bytes ảnh (đã resize ≤1568px cạnh dài, JPEG q85 — spec FR-S3-2,
  /// FR-S4-9) lên signed URL — dùng Dio riêng KHÔNG qua interceptor auth
  /// (URL đã ký, GCS/minio không hiểu Authorization Bearer của app).
  Future<void> uploadBytes({
    required String uploadUrl,
    required Uint8List bytes,
    required String contentType,
  }) async {
    await Dio().put<void>(
      uploadUrl,
      data: bytes,
      options: Options(
        headers: {
          'Content-Type': contentType,
          'Content-Length': bytes.length,
        },
      ),
    );
  }

  /// `POST /photos/:id/review` — enqueue (202) hoặc 402/409/422 (caller xử lý
  /// qua DioException).
  Future<EnqueueReviewResult> enqueueReview(String photoId) async {
    final response = await _dio.post<Map<String, Object?>>(
      '/photos/$photoId/review',
    );
    return EnqueueReviewResult.fromJson(response.data!);
  }

  /// `GET /photos/:id/review` — trạng thái hiện tại (poll).
  Future<ReviewResult> getReview(String photoId) async {
    final response = await _dio.get<Map<String, Object?>>(
      '/photos/$photoId/review',
    );
    return ReviewResult.fromJson(response.data!);
  }
}

final reviewRepositoryProvider = Provider<ReviewRepository>((ref) {
  return ReviewRepository(ref.watch(apiClientProvider));
});
