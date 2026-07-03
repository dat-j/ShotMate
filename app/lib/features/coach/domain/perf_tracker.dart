/// Perf HUD data model + sliding-window tracker (spec-sprint-1 FR-S1-7).
///
/// Pure Dart, không phụ thuộc Flutter — test được không cần widget test
/// harness. Nhận `now` từ ngoài (không dùng clock thật nội bộ) để test
/// deterministic, giống pattern của `HintPrioritizer`
/// (xem `app/lib/features/coach/application/hint_prioritizer.dart`).
///
/// Sprint 1 hiện tại chưa có gì feed sample thật — native inference module
/// + EventChannel timestamps chưa wired (FR-S1-2 chưa implement). Đây là
/// scaffolding: khi FrameAnalysis mang `inferenceLatencyMs` per-detector và
/// timestamp thật chạy qua EventChannel, caller (vd. `coach_state_provider`)
/// sẽ gọi `PerfTracker.record(...)` mỗi frame.
library;

/// Một mẫu latency — có thể là latency per-detector (pose/composition/
/// exposure), channel latency (EventChannel transit time), rule engine time,
/// hoặc frame→hint tổng ("end_to_end").
class PerfSample {
  const PerfSample({
    required this.detector,
    required this.latencyMs,
    required this.timestampMs,
  });

  /// Tên nguồn: 'pose' | 'composition' | 'exposure' | 'channel' |
  /// 'rule_engine' | 'end_to_end' (frame→hint tổng, dùng cho go/no-go gate).
  final String detector;
  final double latencyMs;

  /// epoch ms tại thời điểm sample được ghi nhận — dùng để loại sample
  /// ngoài cửa sổ trượt 10s.
  final int timestampMs;
}

/// Thống kê p50/p90 + fps ước lượng cho một detector trong cửa sổ hiện tại.
class PerfStats {
  const PerfStats({
    required this.detector,
    required this.sampleCount,
    required this.p50Ms,
    required this.p90Ms,
    required this.fps,
  });

  final String detector;
  final int sampleCount;
  final double p50Ms;
  final double p90Ms;

  /// Ước lượng từ sampleCount / cửa sổ (giây). 0 nếu không đủ dữ liệu.
  final double fps;
}

/// Giữ cửa sổ trượt 10s các [PerfSample] theo detector, tính p50/p90 on
/// demand (spec FR-S1-7: "tổng frame→hint p50/p90 (cửa sổ trượt 10s)").
///
/// Stateful có chủ đích, tương tự `HintPrioritizer`: giữ lịch sử sample để
/// tính percentile mà không cần external clock — `now` luôn truyền vào từ
/// caller.
class PerfTracker {
  PerfTracker({this.window = const Duration(seconds: 10)});

  final Duration window;

  final List<PerfSample> _samples = [];

  /// Tất cả sample hiện có (chưa lọc theo cửa sổ) — chủ yếu phục vụ test.
  List<PerfSample> get rawSamples => List.unmodifiable(_samples);

  /// Ghi nhận 1 sample mới. Không tự prune ngay — prune xảy ra khi đọc
  /// (`statsFor` / `allStats`) theo `now` truyền vào, giữ tracker rẻ để gọi
  /// mỗi frame.
  void record(PerfSample sample) => _samples.add(sample);

  void clear() => _samples.clear();

  List<PerfSample> _windowSamples(String detector, DateTime now) {
    final cutoff = now.millisecondsSinceEpoch - window.inMilliseconds;
    return _samples
        .where((s) => s.detector == detector && s.timestampMs >= cutoff)
        .toList();
  }

  /// Danh sách detector đã từng ghi nhận sample trong cửa sổ hiện tại,
  /// thứ tự xuất hiện lần đầu.
  List<String> activeDetectors(DateTime now) {
    final cutoff = now.millisecondsSinceEpoch - window.inMilliseconds;
    final seen = <String>[];
    for (final s in _samples) {
      if (s.timestampMs >= cutoff && !seen.contains(s.detector)) {
        seen.add(s.detector);
      }
    }
    return seen;
  }

  /// p50/p90/fps cho 1 detector trong cửa sổ trượt. Trả stats rỗng (0, 0, 0)
  /// nếu không có sample nào — không throw, để HUD hiển thị "no data" thay
  /// vì crash.
  PerfStats statsFor(String detector, DateTime now) {
    final samples = _windowSamples(detector, now);
    if (samples.isEmpty) {
      return PerfStats(
        detector: detector,
        sampleCount: 0,
        p50Ms: 0,
        p90Ms: 0,
        fps: 0,
      );
    }
    final latencies = samples.map((s) => s.latencyMs).toList()..sort();
    final windowSeconds = window.inMilliseconds / 1000;
    return PerfStats(
      detector: detector,
      sampleCount: samples.length,
      p50Ms: _percentile(latencies, 0.5),
      p90Ms: _percentile(latencies, 0.9),
      fps: windowSeconds > 0 ? samples.length / windowSeconds : 0,
    );
  }

  /// Stats cho toàn bộ detector hiện có trong cửa sổ.
  List<PerfStats> allStats(DateTime now) =>
      activeDetectors(now).map((d) => statsFor(d, now)).toList();

  /// Nearest-rank percentile (0..1) trên danh sách đã sort tăng dần.
  static double _percentile(List<double> sorted, double p) {
    if (sorted.isEmpty) return 0;
    if (sorted.length == 1) return sorted.first;
    final rank = (p * (sorted.length - 1)).round();
    return sorted[rank.clamp(0, sorted.length - 1)];
  }
}
