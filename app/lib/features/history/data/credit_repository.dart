/// Repository cho bảng `credits` (spec-sprint-1 FR-S1-8, Business Rule 4).
///
/// Reset theo ngày địa phương được cài đặt bằng so sánh `day != today` khi
/// đọc (đúng như spec ghi rõ) — KHÔNG cần background job/cron: nếu row của
/// hôm nay chưa tồn tại (hoặc row cũ nhất có `day` khác hôm nay), coi như
/// used=0/quota=10 "ảo" cho tới khi có lượt score đầu tiên trong ngày mới
/// thực sự ghi row mới.
library;

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/database_provider.dart';
import 'app_database.dart';

/// Quota mặc định/ngày (spec Business Rule 4: "Free quota 10 lượt/ngày").
const defaultDailyQuota = 10;

class CreditRepository {
  CreditRepository(this._db);

  final AppDatabase _db;

  /// `YYYY-MM-DD` theo giờ địa phương — key của bảng `credits`.
  String _todayKey([DateTime? now]) {
    final n = now ?? DateTime.now();
    final y = n.year.toString().padLeft(4, '0');
    final m = n.month.toString().padLeft(2, '0');
    final d = n.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  /// Đọc row của hôm nay, nếu chưa có (ngày mới chưa ghi lượt nào) trả về
  /// null — caller coi null == used=0/quota=[defaultDailyQuota].
  Future<Credit?> _todayRow([DateTime? now]) {
    final today = _todayKey(now);
    return (_db.select(_db.credits)..where((t) => t.day.equals(today)))
        .getSingleOrNull();
  }

  /// Còn lượt score hôm nay không (spec FR-S1-8: `used >= quota` → chặn).
  Future<bool> canScore([DateTime? now]) async {
    final row = await _todayRow(now);
    if (row == null) return true; // ngày mới, chưa dùng lượt nào
    return row.used < row.quota;
  }

  /// Số lượt còn lại hôm nay — dùng cho hiển thị UI.
  Future<int> remainingToday([DateTime? now]) async {
    final row = await _todayRow(now);
    if (row == null) return defaultDailyQuota;
    final remaining = row.quota - row.used;
    return remaining < 0 ? 0 : remaining;
  }

  /// Ghi nhận 1 lượt score: `used += 1`. Tạo row mới (used=1) nếu hôm nay
  /// chưa có row (ngày mới — reset "ảo" ở [_todayRow] trở thành thật ở đây).
  Future<void> recordScore([DateTime? now]) async {
    final today = _todayKey(now);
    final existing = await _todayRow(now);
    if (existing == null) {
      await _db.into(_db.credits).insert(
            CreditsCompanion.insert(
              day: today,
              used: const Value(1),
              quota: const Value(defaultDailyQuota),
            ),
          );
      return;
    }
    await (_db.update(_db.credits)..where((t) => t.day.equals(today))).write(
      CreditsCompanion(used: Value(existing.used + 1)),
    );
  }
}

final creditRepositoryProvider = Provider<CreditRepository>((ref) {
  return CreditRepository(ref.watch(databaseProvider));
});
