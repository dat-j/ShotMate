import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shotmate_app/features/history/data/app_database.dart';
import 'package:shotmate_app/features/settings/data/settings_repository.dart';

void main() {
  late AppDatabase db;
  late SettingsRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = SettingsRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('key chưa lưu → trả defaultValue', () async {
    expect(await repo.getBool('x', defaultValue: true), isTrue);
    expect(await repo.getBool('x', defaultValue: false), isFalse);
  });

  test('setBool rồi getBool trả đúng giá trị (persist)', () async {
    await repo.setBool(SettingKeys.smartCountdown, false);
    expect(
      await repo.getBool(SettingKeys.smartCountdown, defaultValue: true),
      isFalse,
    );
  });

  test('setBool ghi đè key có sẵn (upsert)', () async {
    await repo.setBool(SettingKeys.showGrid, false);
    await repo.setBool(SettingKeys.showGrid, true);
    expect(await repo.getBool(SettingKeys.showGrid, defaultValue: false),
        isTrue);
  });

  test('loadToggles trả default khi chưa lưu gì', () async {
    final toggles = await repo.loadToggles();
    expect(toggles[SettingKeys.showGrid], isTrue);
    expect(toggles[SettingKeys.showSkeleton], isFalse);
    expect(toggles[SettingKeys.showPerfHud], isFalse);
    expect(toggles[SettingKeys.smartCountdown], isTrue);
  });

  test('loadToggles phản ánh giá trị đã lưu', () async {
    await repo.setBool(SettingKeys.showGrid, false);
    await repo.setBool(SettingKeys.showPerfHud, true);
    final toggles = await repo.loadToggles();
    expect(toggles[SettingKeys.showGrid], isFalse);
    expect(toggles[SettingKeys.showPerfHud], isTrue);
  });
}
