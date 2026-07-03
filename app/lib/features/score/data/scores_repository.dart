/// Repository cho bảng `scores` (spec-sprint-1 §Database Changes, FR-S1-5,
/// FR-S1-6).
///
/// DB đã có CHECK (0..100) trên từng cột, nhưng repository vẫn clamp trước
/// khi insert — spec Data Validation table yêu cầu rõ "clamp trước khi lưu"
/// ở tầng ứng dụng (fail sớm với dữ liệu rõ ràng, không dựa vào exception từ
/// CHECK constraint để phát hiện lỗi logic phía trên).
library;

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/di/database_provider.dart';
import '../../history/data/app_database.dart';

/// Photo + score mới nhất — dùng cho history list (thumbnail + 4 score +
/// thời gian, spec FR-S1-6) và score screen.
class PhotoWithScore {
  const PhotoWithScore({required this.photo, required this.score});

  final Photo photo;
  final Score? score; // null nếu ảnh chưa có score (vd hết quota — EC-5)
}

class ScoresRepository {
  ScoresRepository(this._db);

  final AppDatabase _db;
  static const _uuid = Uuid();

  /// Insert 1 score record. Mỗi chiều clamp về [0,100] trước khi lưu (spec
  /// Data Validation) dù DB đã có CHECK constraint — phòng vệ 2 lớp.
  Future<String> insertScore({
    required String analysisId,
    required int composition,
    required int lighting,
    required int focus,
    required int background,
  }) async {
    final id = _uuid.v4();
    await _db.into(_db.scores).insert(
          ScoresCompanion.insert(
            id: id,
            analysisId: analysisId,
            composition: composition.clamp(0, 100),
            lighting: lighting.clamp(0, 100),
            focus: focus.clamp(0, 100),
            background: background.clamp(0, 100),
          ),
        );
    return id;
  }

  /// Lấy score theo analysisId — null nếu chưa có (vd bị chặn do hết quota).
  Future<Score?> getByAnalysisId(String analysisId) {
    return (_db.select(_db.scores)
          ..where((t) => t.analysisId.equals(analysisId)))
        .getSingleOrNull();
  }

  /// Score mới nhất của 1 photo — null nếu photo chưa có analysis nào hoặc
  /// analysis mới nhất chưa có score (EC-5: hết quota, vẫn lưu ảnh không
  /// score). Dùng cho Score Screen (spec FR-S1-5), nơi ta chỉ cần 1 photo.
  Future<Score?> getLatestForPhoto(String photoId) async {
    final analysesTable = _db.analyses;
    final query = _db.select(analysesTable)
      ..where((t) => t.photoId.equals(photoId))
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
      ..limit(1);
    final analysis = await query.getSingleOrNull();
    if (analysis == null) return null;
    return getByAnalysisId(analysis.id);
  }

  /// Photo + score mới nhất (theo `analyses.created_at` DESC), trang [page]
  /// (0-based), 30 item/trang — nguồn dữ liệu cho history list (FR-S1-6).
  ///
  /// LEFT JOIN qua analyses vì 1 photo có thể có nhiều analysis (retry) —
  /// lấy analysis mới nhất; LEFT JOIN scores vì photo có thể chưa có score
  /// (EC-5: hết quota giữa session vẫn lưu ảnh, không score).
  Future<List<PhotoWithScore>> getPageWithLatestScore(int page) async {
    final photosTable = _db.photos;
    final analysesTable = _db.analyses;
    final scoresTable = _db.scores;

    final query = _db.select(photosTable).join([
      leftOuterJoin(
        analysesTable,
        analysesTable.photoId.equalsExp(photosTable.id),
      ),
      leftOuterJoin(
        scoresTable,
        scoresTable.analysisId.equalsExp(analysesTable.id),
      ),
    ])
      ..orderBy([
        OrderingTerm.desc(photosTable.takenAt),
        OrderingTerm.desc(analysesTable.createdAt),
      ])
      ..limit(30, offset: page * 30);

    final rows = await query.get();

    // Nhiều analysis/photo có thể sinh nhiều row cho cùng 1 photo (1 row/
    // analysis) — giữ row đầu tiên gặp cho mỗi photo (đã sort mới nhất
    // trước nên đó chính là analysis mới nhất).
    final seen = <String>{};
    final result = <PhotoWithScore>[];
    for (final row in rows) {
      final photo = row.readTable(photosTable);
      if (!seen.add(photo.id)) continue;
      result.add(
        PhotoWithScore(
          photo: photo,
          score: row.readTableOrNull(scoresTable),
        ),
      );
    }
    return result;
  }
}

final scoresRepositoryProvider = Provider<ScoresRepository>((ref) {
  return ScoresRepository(ref.watch(databaseProvider));
});
