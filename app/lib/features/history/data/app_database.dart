/// Drift database (ADR-0005) — schema mirror ERD server để sync Sprint 3
/// không đau (ADR-0002: UUID sinh tại client, cột synced_at từ ngày đầu).
///
/// Schema SQL chuẩn: docs/specs/spec-sprint-1.md §Database Changes.
/// Chạy `dart run build_runner build -d` để sinh app_database.g.dart.
library;

import 'package:drift/drift.dart';

part 'app_database.g.dart';

class Photos extends Table {
  TextColumn get id => text()(); // UUID v4 client-side — BẮT BUỘC (ADR-0002)
  TextColumn get filePath => text()();
  TextColumn get sceneType => text().nullable()(); // Sprint 2: classifier
  TextColumn get captureMeta => text()(); // JSON: zoom, tilt, hints_shown
  IntColumn get takenAt => integer()(); // epoch ms
  IntColumn get syncedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Analyses extends Table {
  TextColumn get id => text()();
  TextColumn get photoId => text().references(Photos, #id)();
  TextColumn get kind => text().withDefault(const Constant('on_device'))();
  TextColumn get provider => text().withDefault(const Constant('rules'))();
  TextColumn get result => text()(); // JSON snapshot + score breakdown
  IntColumn get createdAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Scores extends Table {
  TextColumn get id => text()();
  TextColumn get analysisId => text().references(Analyses, #id)();
  IntColumn get composition => integer()();
  IntColumn get lighting => integer()();
  IntColumn get focus => integer()();
  IntColumn get background => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Credits extends Table {
  TextColumn get day => text()(); // YYYY-MM-DD local (spec FR-S1-8)
  IntColumn get used => integer().withDefault(const Constant(0))();
  IntColumn get quota => integer().withDefault(const Constant(10))();

  @override
  Set<Column<Object>> get primaryKey => {day};
}

@DriftDatabase(tables: [Photos, Analyses, Scores, Credits])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  @override
  int get schemaVersion => 1;
}
