import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mocktail/mocktail.dart';
import 'package:shotmate_app/core/di/database_provider.dart';
import 'package:shotmate_app/features/history/data/app_database.dart';
import 'package:shotmate_app/features/history/data/photos_repository.dart';
import 'package:shotmate_app/features/review/application/review_controller.dart';
import 'package:shotmate_app/features/review/application/review_state.dart';
import 'package:shotmate_app/features/review/data/review_repository.dart';
import 'package:shotmate_app/features/review/domain/review_result.dart';

class _MockReviewRepository extends Mock implements ReviewRepository {}

void main() {
  late AppDatabase db;
  late _MockReviewRepository mockReviewRepo;
  late Directory tempDir;
  late String photoId;
  late ProviderContainer container;

  setUpAll(() {
    registerFallbackValue(Uint8List(0));
  });

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    mockReviewRepo = _MockReviewRepository();
    tempDir = await Directory.systemTemp.createTemp('review_controller_test');

    final photosRepo = PhotosRepository(db);
    final photoFile = File('${tempDir.path}/photo.jpg');
    // Ảnh JPEG hợp lệ nhỏ (10x10) — resizeForUploadInIsolate cần decode
    // được (spec FR-S3-2/FR-S4-9 resize trước upload).
    final syntheticImage = img.Image(width: 10, height: 10);
    await photoFile.writeAsBytes(img.encodeJpg(syntheticImage));

    photoId = await photosRepo.insertPhoto(
      filePath: photoFile.path,
      captureMeta: '{}',
      takenAt: DateTime.fromMillisecondsSinceEpoch(1000),
    );

    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        reviewRepositoryProvider.overrideWithValue(mockReviewRepo),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
    await tempDir.delete(recursive: true);
  });

  ReviewResult doneResult() => const ReviewResult(
        reviewId: 'r1',
        status: 'DONE',
        provider: 'claude',
        scores: ReviewScores(composition: 80, lighting: 70, focus: 90, background: 60),
        explanation: 'Ảnh khá tốt',
        suggestions: ['Nâng máy lên chút'],
        createdAt: '2026-07-06T00:00:00Z',
      );

  test('flow thành công: uploading -> queued -> polling -> done, lưu Drift', () async {
    when(() => mockReviewRepo.requestUploadUrl(
          photoId: any(named: 'photoId'),
          contentType: any(named: 'contentType'),
        )).thenAnswer((_) async => const UploadUrlResult(
          uploadUrl: 'https://upload.example/x',
          storagePath: 'photos/u/p.jpg',
          expiresAt: '2026-07-06T00:15:00Z',
        ));
    when(() => mockReviewRepo.uploadBytes(
          uploadUrl: any(named: 'uploadUrl'),
          bytes: any(named: 'bytes'),
          contentType: any(named: 'contentType'),
        )).thenAnswer((_) async {});
    when(() => mockReviewRepo.enqueueReview(any())).thenAnswer(
      (_) async => const EnqueueReviewResult(
        reviewId: 'r1',
        status: 'QUEUED',
        creditsRemaining: 9,
      ),
    );
    when(() => mockReviewRepo.getReview(any()))
        .thenAnswer((_) async => doneResult());

    final notifier = container.read(reviewControllerProvider(photoId).notifier);
    await notifier.startReview();

    final state = container.read(reviewControllerProvider(photoId));
    expect(state.value, isA<ReviewDone>());
    final done = state.value! as ReviewDone;
    expect(done.result.provider, 'claude');
    expect(done.result.explanation, 'Ảnh khá tốt');

    // Persist vào Drift analyses (kind:cloud, provider:claude) — không đổi
    // schema (spec FR-S3-3).
    final rows = await (db.select(db.analyses)
          ..where((t) => t.photoId.equals(photoId)))
        .get();
    expect(rows, hasLength(1));
    expect(rows.single.kind, 'cloud');
    expect(rows.single.provider, 'claude');
    final decoded = jsonDecode(rows.single.result) as Map<String, Object?>;
    expect(decoded['explanation'], 'Ảnh khá tốt');
  });

  test('402 CREDITS_EXHAUSTED -> failed với thông báo hết lượt', () async {
    when(() => mockReviewRepo.requestUploadUrl(
          photoId: any(named: 'photoId'),
          contentType: any(named: 'contentType'),
        )).thenAnswer((_) async => const UploadUrlResult(
          uploadUrl: 'https://upload.example/x',
          storagePath: 'photos/u/p.jpg',
          expiresAt: '2026-07-06T00:15:00Z',
        ));
    when(() => mockReviewRepo.uploadBytes(
          uploadUrl: any(named: 'uploadUrl'),
          bytes: any(named: 'bytes'),
          contentType: any(named: 'contentType'),
        )).thenAnswer((_) async {});
    when(() => mockReviewRepo.enqueueReview(any())).thenThrow(
      DioException(
        requestOptions: RequestOptions(path: '/photos/$photoId/review'),
        response: Response(
          requestOptions: RequestOptions(path: '/photos/$photoId/review'),
          statusCode: 402,
        ),
        type: DioExceptionType.badResponse,
      ),
    );

    final notifier = container.read(reviewControllerProvider(photoId).notifier);
    await notifier.startReview();

    final state = container.read(reviewControllerProvider(photoId));
    expect(state.value, isA<ReviewFailed>());
    expect((state.value! as ReviewFailed).reason, 'Hết lượt review — nâng cấp');
  });

  test('photo không tồn tại trên đĩa -> failed', () async {
    final photosRepo = PhotosRepository(db);
    final missingPhotoId = await photosRepo.insertPhoto(
      filePath: '${tempDir.path}/khong-ton-tai.jpg',
      captureMeta: '{}',
      takenAt: DateTime.fromMillisecondsSinceEpoch(2000),
    );

    final notifier =
        container.read(reviewControllerProvider(missingPhotoId).notifier);
    await notifier.startReview();

    final state = container.read(reviewControllerProvider(missingPhotoId));
    expect(state.value, isA<ReviewFailed>());
  });
}
