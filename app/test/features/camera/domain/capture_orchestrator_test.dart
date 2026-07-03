import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shotmate_app/features/camera/domain/capture_orchestrator.dart';
import 'package:shotmate_app/features/coach/domain/frame_analysis.dart';
import 'package:shotmate_app/features/history/data/analyses_repository.dart';
import 'package:shotmate_app/features/history/data/app_database.dart';
import 'package:shotmate_app/features/history/data/credit_repository.dart';
import 'package:shotmate_app/features/history/data/photos_repository.dart';
import 'package:shotmate_app/features/score/data/scores_repository.dart';

void main() {
  late AppDatabase db;
  late CaptureOrchestrator orchestrator;
  late PhotosRepository photosRepo;
  late AnalysesRepository analysesRepo;
  late ScoresRepository scoresRepo;
  late CreditRepository creditRepo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    photosRepo = PhotosRepository(db);
    analysesRepo = AnalysesRepository(db);
    scoresRepo = ScoresRepository(db);
    creditRepo = CreditRepository(db);
    orchestrator = CaptureOrchestrator(
      photosRepository: photosRepo,
      analysesRepository: analysesRepo,
      scoresRepository: scoresRepo,
      creditRepository: creditRepo,
    );
  });

  tearDown(() async {
    await db.close();
  });

  test('capture lưu photo + analysis + score khi còn quota', () async {
    final result = await orchestrator.capture(
      filePath: '/data/photos/a.jpg',
      captureMeta: '{}',
      compositionScore: 80,
      analysis: const FrameAnalysis(
        schemaVersion: 1,
        timestampMs: 1000,
        exposure: ExposureInfo(
          meanLuma: 130,
          clippedHighlightsPct: 0,
          clippedShadowsPct: 0,
        ),
      ),
    );

    expect(result.scored, isTrue);

    final photo = await photosRepo.getById(result.photoId);
    expect(photo, isNotNull);
    expect(photo!.filePath, '/data/photos/a.jpg');

    final scoredPage = await scoresRepo.getLatestForPhoto(result.photoId);
    expect(scoredPage, isNotNull);
    expect(scoredPage!.composition, 80);
  });

  test('capture ghi nhận 1 lượt credit khi score thành công', () async {
    await orchestrator.capture(
      filePath: '/data/photos/a.jpg',
      captureMeta: '{}',
      compositionScore: 50,
    );

    final remaining = await creditRepo.remainingToday();
    expect(remaining, defaultDailyQuota - 1);
  });

  test('hết quota (EC-5): ảnh vẫn lưu, KHÔNG tạo score, KHÔNG trừ thêm credit', () async {
    // Dùng hết quota trước.
    for (var i = 0; i < defaultDailyQuota; i++) {
      await creditRepo.recordScore();
    }
    expect(await creditRepo.canScore(), isFalse);

    final result = await orchestrator.capture(
      filePath: '/data/photos/no-score.jpg',
      captureMeta: '{}',
      compositionScore: 60,
    );

    expect(result.scored, isFalse);

    final photo = await photosRepo.getById(result.photoId);
    expect(photo, isNotNull, reason: 'ảnh phải luôn được lưu dù hết quota');

    final score = await scoresRepo.getLatestForPhoto(result.photoId);
    expect(score, isNull);

    final remaining = await creditRepo.remainingToday();
    expect(remaining, 0, reason: 'không được trừ thêm credit khi bị chặn score');
  });

  test('capture không có FrameAnalysis (chưa có frame nào) vẫn hoạt động', () async {
    final result = await orchestrator.capture(
      filePath: '/data/photos/no-analysis.jpg',
      captureMeta: '{}',
      compositionScore: 0,
    );

    expect(result.scored, isTrue);
    final score = await scoresRepo.getLatestForPhoto(result.photoId);
    expect(score, isNotNull);
    // Lighting trung tính (70) khi exposure null — xem PhotoScorer._lightingScore.
    expect(score!.lighting, 70);
  });

  test('mỗi lần gọi capture tạo đúng 1 photo record (không double record)', () async {
    await orchestrator.capture(
      filePath: '/data/photos/x.jpg',
      captureMeta: '{}',
      compositionScore: 10,
    );
    await orchestrator.capture(
      filePath: '/data/photos/y.jpg',
      captureMeta: '{}',
      compositionScore: 20,
    );

    final page = await scoresRepo.getPageWithLatestScore(0);
    expect(page, hasLength(2));
  });
}
