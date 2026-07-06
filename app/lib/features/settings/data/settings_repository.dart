/// Repository cho bảng `settings` (spec-sprint-2 FR-S2-7) — persist toggle qua
/// restart. Value lưu dạng string ('true'/'false' cho bool ở Sprint 2).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/database_provider.dart';
import '../../history/data/app_database.dart';

/// Key các setting (một chỗ, tránh magic string rải rác).
class SettingKeys {
  static const showGrid = 'showGrid';
  static const showSkeleton = 'showSkeleton';
  static const showPerfHud = 'showPerfHud';
  static const smartCountdown = 'smartCountdownEnabled';
}

class SettingsRepository {
  SettingsRepository(this._db);

  final AppDatabase _db;

  Future<bool> getBool(String key, {required bool defaultValue}) async {
    final row = await (_db.select(_db.settings)
          ..where((t) => t.key.equals(key)))
        .getSingleOrNull();
    if (row == null) return defaultValue;
    return row.value == 'true';
  }

  Future<void> setBool(String key, bool value) async {
    await _db.into(_db.settings).insertOnConflictUpdate(
          SettingsCompanion.insert(key: key, value: value ? 'true' : 'false'),
        );
  }

  /// Đọc toàn bộ toggle một lần khi khởi động (seed default nếu chưa có).
  Future<Map<String, bool>> loadToggles() async {
    return {
      SettingKeys.showGrid:
          await getBool(SettingKeys.showGrid, defaultValue: true),
      SettingKeys.showSkeleton:
          await getBool(SettingKeys.showSkeleton, defaultValue: false),
      SettingKeys.showPerfHud:
          await getBool(SettingKeys.showPerfHud, defaultValue: false),
      SettingKeys.smartCountdown:
          await getBool(SettingKeys.smartCountdown, defaultValue: true),
    };
  }
}

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepository(ref.watch(databaseProvider));
});
