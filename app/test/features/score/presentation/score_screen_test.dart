import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shotmate_app/core/di/database_provider.dart';
import 'package:shotmate_app/features/history/data/analyses_repository.dart';
import 'package:shotmate_app/features/history/data/app_database.dart';
import 'package:shotmate_app/features/history/data/photos_repository.dart';
import 'package:shotmate_app/features/score/data/scores_repository.dart';
import 'package:shotmate_app/features/score/presentation/score_screen.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> pumpScoreScreen(WidgetTester tester, String photoId) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(home: ScoreScreen(photoId: photoId)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('hiển thị 4 chiều điểm khi có score', (tester) async {
    final photosRepo = PhotosRepository(db);
    final analysesRepo = AnalysesRepository(db);
    final scoresRepo = ScoresRepository(db);

    final photoId = await photosRepo.insertPhoto(
      filePath: '/data/photos/a.jpg',
      captureMeta: '{}',
      takenAt: DateTime.fromMillisecondsSinceEpoch(1000),
    );
    final analysisId = await analysesRepo.insertAnalysis(
      photoId: photoId,
      result: '{}',
      createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
    );
    await scoresRepo.insertScore(
      analysisId: analysisId,
      composition: 80,
      lighting: 70,
      focus: 90,
      background: 60,
    );

    await pumpScoreScreen(tester, photoId);

    expect(find.text('Composition'), findsOneWidget);
    expect(find.text('80/100'), findsOneWidget);
    expect(find.text('Lighting'), findsOneWidget);
    expect(find.text('70/100'), findsOneWidget);
    expect(find.text('Focus'), findsOneWidget);
    expect(find.text('90/100'), findsOneWidget);
    expect(find.text('Background'), findsOneWidget);
    expect(find.text('60/100'), findsOneWidget);
    expect(find.text('Hết lượt chấm điểm hôm nay'), findsNothing);
  });

  testWidgets('hiển thị message hết quota khi score null (EC-5)', (tester) async {
    final photosRepo = PhotosRepository(db);
    final analysesRepo = AnalysesRepository(db);

    final photoId = await photosRepo.insertPhoto(
      filePath: '/data/photos/no-score.jpg',
      captureMeta: '{}',
      takenAt: DateTime.fromMillisecondsSinceEpoch(2000),
    );
    // Ảnh có analysis nhưng chưa được score (vd hết quota — EC-5).
    await analysesRepo.insertAnalysis(
      photoId: photoId,
      result: '{}',
      createdAt: DateTime.fromMillisecondsSinceEpoch(2000),
    );

    await pumpScoreScreen(tester, photoId);

    expect(find.text('Hết lượt chấm điểm hôm nay'), findsOneWidget);
    expect(find.text('Composition'), findsNothing);
  });

  testWidgets('hiển thị message hết quota khi photo chưa có analysis nào', (tester) async {
    final photosRepo = PhotosRepository(db);

    final photoId = await photosRepo.insertPhoto(
      filePath: '/data/photos/raw.jpg',
      captureMeta: '{}',
      takenAt: DateTime.fromMillisecondsSinceEpoch(3000),
    );

    await pumpScoreScreen(tester, photoId);

    expect(find.text('Hết lượt chấm điểm hôm nay'), findsOneWidget);
  });

  testWidgets('hiển thị "Không tìm thấy ảnh" khi photoId không tồn tại', (tester) async {
    await pumpScoreScreen(tester, 'non-existent-id');

    expect(find.text('Không tìm thấy ảnh'), findsOneWidget);
  });
}
