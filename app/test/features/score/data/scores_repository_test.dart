import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shotmate_app/features/history/data/analyses_repository.dart';
import 'package:shotmate_app/features/history/data/app_database.dart';
import 'package:shotmate_app/features/history/data/photos_repository.dart';
import 'package:shotmate_app/features/score/data/scores_repository.dart';

void main() {
  late AppDatabase db;
  late PhotosRepository photosRepo;
  late AnalysesRepository analysesRepo;
  late ScoresRepository scoresRepo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    photosRepo = PhotosRepository(db);
    analysesRepo = AnalysesRepository(db);
    scoresRepo = ScoresRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<String> seedPhotoAndAnalysis({DateTime? takenAt}) async {
    final photoId = await photosRepo.insertPhoto(
      filePath: '/data/photos/a.jpg',
      captureMeta: '{}',
      takenAt: takenAt ?? DateTime.fromMillisecondsSinceEpoch(1000),
    );
    return analysesRepo.insertAnalysis(
      photoId: photoId,
      result: '{}',
      createdAt: takenAt ?? DateTime.fromMillisecondsSinceEpoch(1000),
    );
  }

  test('insertScore lưu đúng 4 chiều điểm', () async {
    final analysisId = await seedPhotoAndAnalysis();
    final id = await scoresRepo.insertScore(
      analysisId: analysisId,
      composition: 80,
      lighting: 70,
      focus: 90,
      background: 60,
    );

    final score = await scoresRepo.getByAnalysisId(analysisId);
    expect(score, isNotNull);
    expect(score!.id, id);
    expect(score.composition, 80);
    expect(score.lighting, 70);
    expect(score.focus, 90);
    expect(score.background, 60);
  });

  test('getByAnalysisId trả null khi chưa có score', () async {
    final analysisId = await seedPhotoAndAnalysis();
    final score = await scoresRepo.getByAnalysisId(analysisId);
    expect(score, isNull);
  });

  group('clamp phòng vệ (spec Data Validation)', () {
    test('clamp giá trị âm về 0', () async {
      final analysisId = await seedPhotoAndAnalysis();
      await scoresRepo.insertScore(
        analysisId: analysisId,
        composition: -10,
        lighting: -1,
        focus: 0,
        background: -100,
      );
      final score = await scoresRepo.getByAnalysisId(analysisId);
      expect(score!.composition, 0);
      expect(score.lighting, 0);
      expect(score.focus, 0);
      expect(score.background, 0);
    });

    test('clamp giá trị > 100 về 100', () async {
      final analysisId = await seedPhotoAndAnalysis();
      await scoresRepo.insertScore(
        analysisId: analysisId,
        composition: 150,
        lighting: 101,
        focus: 999,
        background: 100,
      );
      final score = await scoresRepo.getByAnalysisId(analysisId);
      expect(score!.composition, 100);
      expect(score.lighting, 100);
      expect(score.focus, 100);
      expect(score.background, 100);
    });
  });

  group('getPageWithLatestScore (join cho history)', () {
    test('trả photo kèm score mới nhất, mới nhất trước', () async {
      final analysisId1 = await seedPhotoAndAnalysis(
        takenAt: DateTime.fromMillisecondsSinceEpoch(1000),
      );
      await scoresRepo.insertScore(
        analysisId: analysisId1,
        composition: 50,
        lighting: 50,
        focus: 50,
        background: 50,
      );

      final analysisId2 = await seedPhotoAndAnalysis(
        takenAt: DateTime.fromMillisecondsSinceEpoch(2000),
      );
      await scoresRepo.insertScore(
        analysisId: analysisId2,
        composition: 90,
        lighting: 91,
        focus: 92,
        background: 93,
      );

      final page = await scoresRepo.getPageWithLatestScore(0);
      expect(page, hasLength(2));
      expect(page.first.photo.takenAt, 2000);
      expect(page.first.score!.composition, 90);
      expect(page.last.photo.takenAt, 1000);
      expect(page.last.score!.composition, 50);
    });

    test('photo chưa có score (EC-5) trả score null, không loại khỏi list', () async {
      final photoId = await photosRepo.insertPhoto(
        filePath: '/data/photos/no-score.jpg',
        captureMeta: '{}',
        takenAt: DateTime.fromMillisecondsSinceEpoch(3000),
      );
      // Ảnh có analysis nhưng chưa được score (vd hết quota).
      await analysesRepo.insertAnalysis(
        photoId: photoId,
        result: '{}',
        createdAt: DateTime.fromMillisecondsSinceEpoch(3000),
      );

      final page = await scoresRepo.getPageWithLatestScore(0);
      expect(page, hasLength(1));
      expect(page.first.photo.id, photoId);
      expect(page.first.score, isNull);
    });

    test('photo hoàn toàn không có analysis vẫn xuất hiện trong list', () async {
      final photoId = await photosRepo.insertPhoto(
        filePath: '/data/photos/raw.jpg',
        captureMeta: '{}',
        takenAt: DateTime.fromMillisecondsSinceEpoch(4000),
      );

      final page = await scoresRepo.getPageWithLatestScore(0);
      expect(page, hasLength(1));
      expect(page.first.photo.id, photoId);
      expect(page.first.score, isNull);
    });

    test('mỗi photo chỉ xuất hiện 1 lần dù có nhiều analysis (retry)', () async {
      final photoId = await photosRepo.insertPhoto(
        filePath: '/data/photos/retry.jpg',
        captureMeta: '{}',
        takenAt: DateTime.fromMillisecondsSinceEpoch(5000),
      );
      await analysesRepo.insertAnalysis(
        photoId: photoId,
        result: '{}',
        createdAt: DateTime.fromMillisecondsSinceEpoch(5000),
      );
      final latestAnalysisId = await analysesRepo.insertAnalysis(
        photoId: photoId,
        result: '{}',
        createdAt: DateTime.fromMillisecondsSinceEpoch(5100),
      );
      await scoresRepo.insertScore(
        analysisId: latestAnalysisId,
        composition: 77,
        lighting: 77,
        focus: 77,
        background: 77,
      );

      final page = await scoresRepo.getPageWithLatestScore(0);
      final matches = page.where((p) => p.photo.id == photoId).toList();
      expect(matches, hasLength(1));
      expect(matches.first.score!.composition, 77);
    });
  });
}
