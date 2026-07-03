/// DI cho [AppDatabase] (ADR-0005) — nguồn duy nhất tạo instance DB, mọi
/// repository phụ thuộc vào provider này qua `ref.watch` (đúng tinh thần
/// "provider chính là DI container" của codebase — xem coach_state_provider).
///
/// Dùng `LazyDatabase` để việc tìm `getApplicationDocumentsDirectory()` và
/// mở file SQLite chỉ xảy ra khi có query đầu tiên, không chặn app khởi động.
library;

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../features/history/data/app_database.dart';

/// Instance [AppDatabase] dùng chung toàn app — file SQLite trong app
/// documents directory (app-private, spec-sprint-1 Sensitive Data).
final databaseProvider = Provider<AppDatabase>((ref) {
  final database = AppDatabase(_openConnection());
  ref.onDispose(database.close);
  return database;
});

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'shotmate.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
