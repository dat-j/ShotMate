/// Smart Countdown — tự chụp khi ánh sáng đang đẹp dần (spec-sprint-2 FR-S2-6,
/// Business Rule 7).
///
/// Pure state machine, deterministic: nhận chuỗi observation + `now` từ ngoài
/// (giống HintPrioritizer/PerfTracker) → test được không cần clock thật.
///
/// idle → proposed (luma tăng ≥15%/3s, không critical) → counting(3,2,1)
///   → firing (báo caller chụp) | cancelled(reason)
///
/// Caller (widget) đọc [state] mỗi frame, gọi [tick]; khi [state.phase] thành
/// [CountdownPhase.firing] thì gọi capture flow chuẩn, rồi [reset].
library;

/// Một mẫu luma theo thời gian, cho cửa sổ trượt trend.
class _LumaSample {
  const _LumaSample(this.luma, this.atMs);
  final double luma;
  final int atMs;
}

enum CountdownPhase { idle, proposed, counting, firing, cancelled }

class CountdownState {
  const CountdownState({
    required this.phase,
    this.secondsLeft = 0,
    this.cancelReason,
  });

  final CountdownPhase phase;

  /// 3,2,1 khi đang counting; 0 ngoài counting.
  final int secondsLeft;

  /// Lý do huỷ ≤ 30 ký tự (chỉ khi phase == cancelled).
  final String? cancelReason;

  static const idle = CountdownState(phase: CountdownPhase.idle);
}

class CountdownConfig {
  const CountdownConfig({
    this.enabled = true,
    this.trendWindow = const Duration(seconds: 3),
    this.improveThresholdPct = 15,
    this.cooldown = const Duration(seconds: 30),
    this.lumaDropCancelPct = 5,
  });

  final bool enabled;
  final Duration trendWindow;

  /// % tăng luma tối thiểu trong cửa sổ để đề xuất.
  final double improveThresholdPct;
  final Duration cooldown;

  /// % giảm so đỉnh trong khi đếm → huỷ.
  final double lumaDropCancelPct;
}

class CountdownController {
  CountdownController({this.config = const CountdownConfig()});

  final CountdownConfig config;

  final List<_LumaSample> _lumaHistory = [];
  CountdownState _state = CountdownState.idle;
  int? _countStartMs;
  double _peakLumaWhileCounting = 0;
  int _lastProposalEndMs = -1 << 30; // rất xa quá khứ

  CountdownState get state => _state;

  /// Nạp 1 quan sát. [meanLuma] từ exposure; [hasCritical] có hint critical
  /// đang hiển thị; [manualCapture] user vừa bấm shutter tay; [nowMs] thời
  /// điểm hiện tại.
  CountdownState tick({
    required double? meanLuma,
    required bool hasCritical,
    required bool manualCapture,
    required int nowMs,
  }) {
    if (!config.enabled) return _state = CountdownState.idle;

    // Chụp tay luôn thắng (EC-S2-2).
    if (manualCapture && _state.phase == CountdownPhase.counting) {
      return _resetToIdle();
    }

    if (meanLuma != null) {
      _lumaHistory.add(_LumaSample(meanLuma, nowMs));
      _pruneLuma(nowMs);
    }

    switch (_state.phase) {
      case CountdownPhase.idle:
      case CountdownPhase.cancelled:
      case CountdownPhase.firing:
        return _maybePropose(hasCritical, nowMs);
      case CountdownPhase.proposed:
        // proposed là trạng thái chờ user bấm "bắt đầu" — huỷ nếu critical xuất
        // hiện; ngược lại giữ.
        if (hasCritical) return _cancel('Có vấn đề bố cục', nowMs);
        return _state;
      case CountdownPhase.counting:
        return _advanceCounting(meanLuma, hasCritical, nowMs);
    }
  }

  /// User chấp nhận đề xuất → bắt đầu đếm.
  CountdownState start(int nowMs) {
    if (_state.phase != CountdownPhase.proposed) return _state;
    _countStartMs = nowMs;
    _peakLumaWhileCounting = _latestLuma() ?? 0;
    return _state = const CountdownState(
      phase: CountdownPhase.counting,
      secondsLeft: 3,
    );
  }

  /// User huỷ thủ công.
  CountdownState cancelByUser(int nowMs) => _cancel('Đã huỷ', nowMs);

  void reset() => _resetToIdle();

  // --- internal ---

  CountdownState _maybePropose(bool hasCritical, int nowMs) {
    if (hasCritical) return _state = CountdownState.idle;
    if (nowMs - _lastProposalEndMs < config.cooldown.inMilliseconds) {
      return _state = CountdownState.idle;
    }
    if (_lumaImprovementPct(nowMs) >= config.improveThresholdPct) {
      return _state = const CountdownState(phase: CountdownPhase.proposed);
    }
    return _state = CountdownState.idle;
  }

  CountdownState _advanceCounting(
      double? meanLuma, bool hasCritical, int nowMs) {
    if (hasCritical) return _cancel('Ánh sáng/bố cục xấu đi', nowMs);
    if (meanLuma != null) {
      if (meanLuma > _peakLumaWhileCounting) _peakLumaWhileCounting = meanLuma;
      final dropPct = _peakLumaWhileCounting > 0
          ? (_peakLumaWhileCounting - meanLuma) / _peakLumaWhileCounting * 100
          : 0;
      if (dropPct > config.lumaDropCancelPct) {
        return _cancel('Ánh sáng xấu đi', nowMs);
      }
    }
    final elapsed = nowMs - (_countStartMs ?? nowMs);
    final secondsLeft = 3 - (elapsed ~/ 1000);
    if (secondsLeft <= 0) {
      _lastProposalEndMs = nowMs;
      return _state = const CountdownState(phase: CountdownPhase.firing);
    }
    return _state = CountdownState(
      phase: CountdownPhase.counting,
      secondsLeft: secondsLeft,
    );
  }

  CountdownState _cancel(String reason, int nowMs) {
    _countStartMs = null;
    _lastProposalEndMs = nowMs;
    return _state =
        CountdownState(phase: CountdownPhase.cancelled, cancelReason: reason);
  }

  CountdownState _resetToIdle() {
    _countStartMs = null;
    return _state = CountdownState.idle;
  }

  void _pruneLuma(int nowMs) {
    final cutoff = nowMs - config.trendWindow.inMilliseconds;
    _lumaHistory.removeWhere((s) => s.atMs < cutoff);
  }

  double? _latestLuma() =>
      _lumaHistory.isEmpty ? null : _lumaHistory.last.luma;

  /// % tăng từ mẫu cũ nhất → mới nhất trong cửa sổ. 0 nếu không đủ dữ liệu
  /// hoặc không tăng.
  double _lumaImprovementPct(int nowMs) {
    if (_lumaHistory.length < 2) return 0;
    final oldest = _lumaHistory.first;
    final newest = _lumaHistory.last;
    // Cần trải đủ (gần) hết cửa sổ để trend có ý nghĩa.
    if (newest.atMs - oldest.atMs < config.trendWindow.inMilliseconds * 0.8) {
      return 0;
    }
    if (oldest.luma <= 0) return 0;
    final pct = (newest.luma - oldest.luma) / oldest.luma * 100;
    return pct > 0 ? pct : 0;
  }
}
