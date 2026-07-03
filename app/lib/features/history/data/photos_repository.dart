/// Repository cho bảng `photos` (spec-sprint-1 §Database Changes, FR-S1-6).
///
/// UUID sinh tại client (ADR-0002, bắt buộc cho sync Sprint 3) — dùng package
/// `uuid` thay vì để DB tự sinh id, vì Drift/SQLite không có UUID builtin và
/// client cần biết id ngay sau insert (ví dụ để tạo Analysis/Score liên kết).
library;

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/di/database_provider.dart';
import 'app_database.dart';

/// Số ảnh/trang cho history list (spec FR-S1-6: "phân trang 30/lần").
const historyPageSize = 30;

class PhotosRepository {
  PhotosRepository(this._db);

  final AppDatabase _db;
  static const _uuid = Uuid();

  /// Insert 1 photo record, trả về id (UUID v4) vừa tạo.
  ///
  /// [captureMeta] là JSON string đã serialize sẵn (zoom, tilt, hints_shown —
  /// spec §Database Changes) — repository không biết về cấu trúc capture
  /// meta, chỉ lưu chuỗi (tránh coupling ngược vào tầng capture flow).
  Future<String> insertPhoto({
    required String filePath,
    required String captureMeta,
    required DateTime takenAt,
    String? sceneType,
  }) async {
    final id = _uuid.v4();
    await _db.into(_db.photos).insert(
          PhotosCompanion.insert(
            id: id,
            filePath: filePath,
            captureMeta: captureMeta,
            takenAt: takenAt.millisecondsSinceEpoch,
            sceneType: Value(sceneType),
          ),
        );
    return id;
  }

  /// Trang [page] (0-based) của history, mới nhất trước, 30 item/trang
  /// (spec FR-S1-6). Index `idx_photos_taken_at` đảm bảo query < 50ms
  /// (spec NFR Performance) dù DB có 10k ảnh.
  Future<List<Photo>> getPage(int page) {
    final query = _db.select(_db.photos)
      ..orderBy([(t) => OrderingTerm.desc(t.takenAt)])
      ..limit(historyPageSize, offset: page * historyPageSize);
    return query.get();
  }

  /// Lấy 1 photo theo id — null nếu không tồn tại.
  Future<Photo?> getById(String id) {
    return (_db.select(_db.photos)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }
}

/// DI: repository phụ thuộc [databaseProvider] — nguồn DB instance duy nhất.
final photosRepositoryProvider = Provider<PhotosRepository>((ref) {
  return PhotosRepository(ref.watch(databaseProvider));
});
