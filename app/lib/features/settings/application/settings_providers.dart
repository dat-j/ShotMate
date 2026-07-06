/// State toggles cho SettingsScreen (spec-sprint-1 FR-S1-4/7, spec-sprint-2
/// FR-S2-7: persist qua restart bằng Drift).
///
/// Mỗi toggle là [ToggleNotifier] đọc giá trị đầu từ Drift (bảng `settings`)
/// và ghi lại mỗi khi đổi. Giá trị mặc định dùng ngay lập tức (đồng bộ), Drift
/// nạp bất đồng bộ và cập nhật khi xong — tránh chớp UI lúc khởi động.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/settings_repository.dart';

class ToggleNotifier extends Notifier<bool> {
  ToggleNotifier(this._key, this._defaultValue);

  final String _key;
  final bool _defaultValue;

  @override
  bool build() {
    // Nạp giá trị đã lưu (async) rồi cập nhật state.
    final repo = ref.watch(settingsRepositoryProvider);
    repo.getBool(_key, defaultValue: _defaultValue).then((v) {
      if (v != state) state = v;
    });
    return _defaultValue;
  }

  /// Đổi + persist.
  Future<void> set(bool value) async {
    state = value;
    await ref.read(settingsRepositoryProvider).setBool(_key, value);
  }
}

/// Lưới rule-of-thirds trên overlay, mặc định bật (FR-S1-4).
final showGridProvider = NotifierProvider<ToggleNotifier, bool>(
  () => ToggleNotifier(SettingKeys.showGrid, true),
);

/// Skeleton dots (pose landmarks) debug, mặc định tắt (FR-S1-4).
final showSkeletonProvider = NotifierProvider<ToggleNotifier, bool>(
  () => ToggleNotifier(SettingKeys.showSkeleton, false),
);

/// Perf HUD (debug builds), mặc định tắt (FR-S1-7).
final showPerfHudProvider = NotifierProvider<ToggleNotifier, bool>(
  () => ToggleNotifier(SettingKeys.showPerfHud, false),
);

/// Smart Countdown tự chụp (spec-sprint-2 FR-S2-6/7), mặc định bật.
final smartCountdownEnabledProvider = NotifierProvider<ToggleNotifier, bool>(
  () => ToggleNotifier(SettingKeys.smartCountdown, true),
);
