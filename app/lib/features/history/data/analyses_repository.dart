/// Repository cho bảng `analyses` (spec-sprint-1 §Database Changes).
///
/// Sprint 1 chỉ có 1 nguồn phân tích: rule engine on-device (`kind:
/// 'on_device'`, `provider: 'rules'` — mặc định đã khai báo ở
/// [Analyses] table). Cloud review (Claude/Gemini) là Sprint 3+ (ADR-0004),
/// khi đó sẽ thêm `kind`/`provider` khác qua tham số, không đổi schema.
library;

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/di/database_provider.dart';
import 'app_database.dart';

class AnalysesRepository {
  AnalysesRepository(this._db);

  final AppDatabase _db;
  static const _uuid = Uuid();

  /// Insert 1 analysis record (FrameAnalysis snapshot + score breakdown dạng
  /// JSON string — spec: "JSON FrameAnalysis snapshot + score breakdown").
  /// Trả về id (UUID v4) vừa tạo, dùng làm FK cho [ScoresRepository].
  Future<String> insertAnalysis({
    required String photoId,
    required String result,
    required DateTime createdAt,
    String kind = 'on_device',
    String provider = 'rules',
  }) async {
    final id = _uuid.v4();
    await _db.into(_db.analyses).insert(
          AnalysesCompanion.insert(
            id: id,
            photoId: photoId,
            result: result,
            createdAt: createdAt.millisecondsSinceEpoch,
            kind: Value(kind),
            provider: Value(provider),
          ),
        );
    return id;
  }

  /// Lấy 1 analysis theo id — null nếu không tồn tại.
  Future<Analyse?> getById(String id) {
    return (_db.select(_db.analyses)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }
}

final analysesRepositoryProvider = Provider<AnalysesRepository>((ref) {
  return AnalysesRepository(ref.watch(databaseProvider));
});
