/// Wiring CountdownController vào stream (spec-sprint-2 FR-S2-6).
///
/// Tick controller mỗi frame với luma + có critical hint + setting enabled.
/// Widget đọc state để hiển thị banner/số đếm; khi phase == firing, widget gọi
/// capture rồi [CountdownNotifier.reset].
///
/// `manualCapture` (chụp tay thắng — EC-S2-2) do widget báo qua [notifyManual].
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/frame_analysis_channel.dart';
import '../../settings/application/settings_providers.dart';
import '../domain/coach_hint.dart';
import '../domain/countdown_controller.dart';
import 'coach_state_provider.dart';

class CountdownNotifier extends Notifier<CountdownState> {
  CountdownController _controller = CountdownController();
  bool _pendingManual = false;

  @override
  CountdownState build() {
    // Setting enabled đổi → thay config nhưng GIỮ controller state khác
    // (lumaHistory/count). CountdownController.config là final nên khi enabled
    // đổi ta tạo mới — chấp nhận reset trend (đổi setting hiếm, không phá UX).
    final enabled = ref.watch(smartCountdownEnabledProvider);
    if (_controller.config.enabled != enabled) {
      _controller = CountdownController(config: CountdownConfig(enabled: enabled));
    }

    final analysis = ref.watch(frameAnalysisStreamProvider).valueOrNull;
    final coach = ref.watch(coachStateProvider);
    if (analysis == null) return CountdownState.idle;

    final hasCritical =
        coach.hints.any((h) => h.severity == HintSeverity.critical);
    final manual = _pendingManual;
    _pendingManual = false;

    return _controller.tick(
      meanLuma: analysis.exposure?.meanLuma,
      hasCritical: hasCritical,
      manualCapture: manual,
      nowMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// User bấm "bắt đầu" trên banner đề xuất.
  void start() {
    state = _controller.start(DateTime.now().millisecondsSinceEpoch);
  }

  /// User huỷ.
  void cancel() {
    state = _controller.cancelByUser(DateTime.now().millisecondsSinceEpoch);
  }

  /// Báo user vừa chụp tay (EC-S2-2) — sẽ áp dụng ở tick kế tiếp.
  void notifyManual() => _pendingManual = true;

  /// Sau khi widget đã xử lý firing (chụp xong).
  void reset() {
    _controller.reset();
    state = CountdownState.idle;
  }
}

final countdownProvider =
    NotifierProvider<CountdownNotifier, CountdownState>(CountdownNotifier.new);
