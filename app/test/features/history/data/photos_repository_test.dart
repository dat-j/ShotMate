import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shotmate_app/features/history/data/app_database.dart';
import 'package:shotmate_app/features/history/data/photos_repository.dart';

void main() {
  late AppDatabase db;
  late PhotosRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = PhotosRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('insertPhoto sinh UUID v4 và lưu đúng field', () async {
    final takenAt = DateTime.fromMillisecondsSinceEpoch(1000);
    final id = await repo.insertPhoto(
      filePath: '/data/photos/a.jpg',
      captureMeta: '{"zoom":1.0}',
      takenAt: takenAt,
    );

    expect(id, isNotEmpty);
    // UUID v4 format: 8-4-4-4-12 hex, version nibble '4'.
    expect(
      id,
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );

    final photo = await repo.getById(id);
    expect(photo, isNotNull);
    expect(photo!.filePath, '/data/photos/a.jpg');
    expect(photo.captureMeta, '{"zoom":1.0}');
    expect(photo.takenAt, 1000);
    expect(photo.sceneType, isNull);
    expect(photo.syncedAt, isNull);
  });

  test('getById trả null khi không tồn tại', () async {
    final photo = await repo.getById('missing-id');
    expect(photo, isNull);
  });

  test('getPage trả về mới nhất trước, đúng kích thước trang', () async {
    for (var i = 0; i < 35; i++) {
      await repo.insertPhoto(
        filePath: '/data/photos/$i.jpg',
        captureMeta: '{}',
        takenAt: DateTime.fromMillisecondsSinceEpoch(i * 1000),
      );
    }

    final page0 = await repo.getPage(0);
    expect(page0, hasLength(30));
    // Ảnh mới nhất (i=34, takenAt lớn nhất) phải đứng đầu.
    expect(page0.first.filePath, '/data/photos/34.jpg');
    expect(page0.last.filePath, '/data/photos/5.jpg');

    final page1 = await repo.getPage(1);
    expect(page1, hasLength(5));
    expect(page1.first.filePath, '/data/photos/4.jpg');
    expect(page1.last.filePath, '/data/photos/0.jpg');
  });

  test('getPage trả rỗng khi không có ảnh', () async {
    final page = await repo.getPage(0);
    expect(page, isEmpty);
  });
}
