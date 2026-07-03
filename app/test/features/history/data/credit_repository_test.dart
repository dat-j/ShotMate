import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shotmate_app/features/history/data/app_database.dart';
import 'package:shotmate_app/features/history/data/credit_repository.dart';

void main() {
  late AppDatabase db;
  late CreditRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = CreditRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('ngày mới (chưa có row) bắt đầu used=0, remainingToday = quota mặc định', () async {
    expect(await repo.remainingToday(), defaultDailyQuota);
    expect(await repo.canScore(), isTrue);
  });

  test('canScore() true khi còn dưới quota', () async {
    for (var i = 0; i < 5; i++) {
      await repo.recordScore();
    }
    expect(await repo.canScore(), isTrue);
    expect(await repo.remainingToday(), defaultDailyQuota - 5);
  });

  test('recordScore() tăng used, tạo row nếu chưa có', () async {
    await repo.recordScore();
    expect(await repo.remainingToday(), defaultDailyQuota - 1);

    await repo.recordScore();
    expect(await repo.remainingToday(), defaultDailyQuota - 2);
  });

  test('hết quota (used>=10) chặn canScore()', () async {
    for (var i = 0; i < defaultDailyQuota; i++) {
      await repo.recordScore();
    }
    expect(await repo.remainingToday(), 0);
    expect(await repo.canScore(), isFalse);
  });

  test('recordScore() quá quota vẫn tăng used (không tự chặn ghi — caller kiểm tra canScore trước)', () async {
    for (var i = 0; i < defaultDailyQuota + 2; i++) {
      await repo.recordScore();
    }
    expect(await repo.canScore(), isFalse);
    expect(await repo.remainingToday(), 0); // clamp về 0, không âm
  });

  group('reset theo ngày (Business Rule 4: so sánh day != today khi đọc)', () {
    test('row của hôm qua bị bỏ qua — hôm nay đọc như ngày mới', () async {
      // Chèn thẳng 1 row "hôm qua" đã dùng hết quota.
      await db.into(db.credits).insert(
            CreditsCompanion.insert(
              day: '2020-01-01',
              used: const Value(defaultDailyQuota),
              quota: const Value(defaultDailyQuota),
            ),
          );

      // Không truyền `now` — dùng DateTime.now() thật, chắc chắn khác
      // '2020-01-01' nên phải đọc như ngày mới (used=0).
      expect(await repo.canScore(), isTrue);
      expect(await repo.remainingToday(), defaultDailyQuota);
    });

    test('recordScore() ở ngày mới tạo row riêng, không cộng dồn vào row cũ', () async {
      await db.into(db.credits).insert(
            CreditsCompanion.insert(
              day: '2020-01-01',
              used: const Value(defaultDailyQuota),
              quota: const Value(defaultDailyQuota),
            ),
          );

      await repo.recordScore();

      expect(await repo.remainingToday(), defaultDailyQuota - 1);

      // Row cũ của hôm qua vẫn còn nguyên, không bị ghi đè.
      final oldRow = await (db.select(db.credits)
            ..where((t) => t.day.equals('2020-01-01')))
          .getSingle();
      expect(oldRow.used, defaultDailyQuota);
    });

    test('giả lập rollover bằng `now` tường minh: ngày khác đọc độc lập', () async {
      final day1 = DateTime(2024, 1, 1);
      final day2 = DateTime(2024, 1, 2);

      await repo.recordScore(day1);
      await repo.recordScore(day1);
      expect(await repo.remainingToday(day1), defaultDailyQuota - 2);

      // Ngày kế tiếp: hoàn toàn độc lập, không kế thừa used của day1.
      expect(await repo.canScore(day2), isTrue);
      expect(await repo.remainingToday(day2), defaultDailyQuota);

      await repo.recordScore(day2);
      expect(await repo.remainingToday(day2), defaultDailyQuota - 1);
      // day1 không đổi.
      expect(await repo.remainingToday(day1), defaultDailyQuota - 2);
    });
  });
}
