import 'package:flutter_test/flutter_test.dart';
import 'package:shotmate_app/features/coach/domain/perf_tracker.dart';

void main() {
  group('PerfTracker.statsFor', () {
    test('empty tracker trả stats mặc định (0) không throw', () {
      final tracker = PerfTracker();
      final stats = tracker.statsFor('pose', DateTime(2026, 1, 1));
      expect(stats.sampleCount, 0);
      expect(stats.p50Ms, 0);
      expect(stats.p90Ms, 0);
      expect(stats.fps, 0);
    });

    test('p50/p90 tính đúng cho tập sample đã biết', () {
      final tracker = PerfTracker();
      final now = DateTime(2026, 1, 1, 12, 0, 0);
      final baseMs = now.millisecondsSinceEpoch;
      // 10 sample latency 10..100ms, cách đều trong cửa sổ 10s.
      final latencies = List.generate(10, (i) => (i + 1) * 10.0);
      for (final latency in latencies) {
        tracker.record(PerfSample(
          detector: 'pose',
          latencyMs: latency,
          timestampMs: baseMs,
        ));
      }

      final stats = tracker.statsFor('pose', now);
      expect(stats.sampleCount, 10);
      // nearest-rank: p50 -> index round(0.5*9)=5 -> giá trị thứ 6 = 60
      expect(stats.p50Ms, 60.0);
      // p90 -> index round(0.9*9)=8 -> giá trị thứ 9 = 90
      expect(stats.p90Ms, 90.0);
    });

    test('single sample: p50 == p90 == latency đó', () {
      final tracker = PerfTracker();
      final now = DateTime(2026, 1, 1);
      tracker.record(PerfSample(
        detector: 'exposure',
        latencyMs: 42,
        timestampMs: now.millisecondsSinceEpoch,
      ));

      final stats = tracker.statsFor('exposure', now);
      expect(stats.p50Ms, 42);
      expect(stats.p90Ms, 42);
      expect(stats.sampleCount, 1);
    });

    test('fps ước lượng từ sampleCount / cửa sổ 10s', () {
      final tracker = PerfTracker();
      final now = DateTime(2026, 1, 1);
      final baseMs = now.millisecondsSinceEpoch;
      // 50 sample trong 10s → 5fps.
      for (var i = 0; i < 50; i++) {
        tracker.record(PerfSample(
          detector: 'composition',
          latencyMs: 5,
          timestampMs: baseMs,
        ));
      }

      final stats = tracker.statsFor('composition', now);
      expect(stats.fps, 5.0);
    });
  });

  group('cửa sổ trượt 10s', () {
    test('sample cũ hơn 10s bị loại khỏi tính toán', () {
      final tracker = PerfTracker();
      final t0 = DateTime(2026, 1, 1, 12, 0, 0);

      // Sample tại t0 (sẽ hết hạn).
      tracker.record(PerfSample(
        detector: 'pose',
        latencyMs: 999,
        timestampMs: t0.millisecondsSinceEpoch,
      ));

      // now = t0 + 11s → sample trên ngoài cửa sổ 10s.
      final now = t0.add(const Duration(seconds: 11));
      final stats = tracker.statsFor('pose', now);
      expect(stats.sampleCount, 0);
      expect(stats.p50Ms, 0);
    });

    test('sample trong biên 10s vẫn được tính, sample vừa ngoài biên bị loại', () {
      final tracker = PerfTracker();
      final t0 = DateTime(2026, 1, 1, 12, 0, 0);
      final baseMs = t0.millisecondsSinceEpoch;

      tracker.record(PerfSample(
        detector: 'pose',
        latencyMs: 10,
        timestampMs: baseMs,
      ));
      final now = t0.add(const Duration(seconds: 10));
      // now - window(10s) == baseMs → vẫn nằm trong cửa sổ (inclusive).
      expect(tracker.statsFor('pose', now).sampleCount, 1);

      final justOutside = t0.add(const Duration(seconds: 10, milliseconds: 1));
      expect(tracker.statsFor('pose', justOutside).sampleCount, 0);
    });

    test('mix sample mới và cũ: chỉ sample trong cửa sổ được tính', () {
      final tracker = PerfTracker();
      final t0 = DateTime(2026, 1, 1, 12, 0, 0);

      tracker.record(PerfSample(
        detector: 'pose',
        latencyMs: 999,
        timestampMs: t0.millisecondsSinceEpoch,
      )); // sẽ hết hạn
      final now = t0.add(const Duration(seconds: 12));
      tracker.record(PerfSample(
        detector: 'pose',
        latencyMs: 20,
        timestampMs: now.millisecondsSinceEpoch,
      )); // còn mới

      final stats = tracker.statsFor('pose', now);
      expect(stats.sampleCount, 1);
      expect(stats.p50Ms, 20);
    });
  });

  group('allStats / activeDetectors', () {
    test('trả danh sách detector đang có sample trong cửa sổ', () {
      final tracker = PerfTracker();
      final now = DateTime(2026, 1, 1);
      final baseMs = now.millisecondsSinceEpoch;
      tracker
        ..record(PerfSample(detector: 'pose', latencyMs: 10, timestampMs: baseMs))
        ..record(PerfSample(
            detector: 'composition', latencyMs: 20, timestampMs: baseMs))
        ..record(PerfSample(
            detector: 'end_to_end', latencyMs: 80, timestampMs: baseMs));

      final detectors = tracker.activeDetectors(now);
      expect(detectors, containsAll(['pose', 'composition', 'end_to_end']));

      final allStats = tracker.allStats(now);
      expect(allStats.length, 3);
    });

    test('allStats rỗng khi tracker rỗng', () {
      final tracker = PerfTracker();
      expect(tracker.allStats(DateTime(2026, 1, 1)), isEmpty);
    });
  });

  group('clear', () {
    test('xoá toàn bộ sample', () {
      final tracker = PerfTracker();
      final now = DateTime(2026, 1, 1);
      tracker.record(PerfSample(
          detector: 'pose',
          latencyMs: 10,
          timestampMs: now.millisecondsSinceEpoch));
      tracker.clear();
      expect(tracker.statsFor('pose', now).sampleCount, 0);
      expect(tracker.rawSamples, isEmpty);
    });
  });
}
