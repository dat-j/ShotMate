/// PerfHud — overlay debug hiển thị fps/latency per-detector + frame→hint
/// p50/p90 (spec-sprint-1 FR-S1-7, debug builds only).
///
/// Widget này KHÔNG tự gate bằng `kDebugMode` / `showPerfHudProvider` — nó
/// chỉ đọc [perfTrackerProvider] và render những gì đang có. Caller (nơi
/// compose vào camera_screen.dart) chịu trách nhiệm mount có điều kiện:
///
/// ```dart
/// if (kDebugMode && ref.watch(showPerfHudProvider)) const PerfHud(),
/// ```
///
/// Việc wiring vào camera_screen.dart nằm ngoài scope hiện tại (tránh xung
/// đột với worker khác đang sửa file đó) — xem settings_providers.dart.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/perf_tracker_provider.dart';
import '../domain/perf_tracker.dart';

class PerfHud extends ConsumerStatefulWidget {
  const PerfHud({super.key});

  @override
  ConsumerState<PerfHud> createState() => _PerfHudState();
}

class _PerfHudState extends ConsumerState<PerfHud> {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    // PerfTracker.record() không notify Riverpod (giữ tracker rẻ, gọi mỗi
    // frame) — HUD tự poll để hiển thị cửa sổ trượt cập nhật.
    _refreshTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) {
        if (mounted) setState(() {});
      },
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tracker = ref.watch(perfTrackerProvider);
    final now = DateTime.now();
    final stats = tracker.allStats(now);
    final endToEnd = tracker.statsFor('end_to_end', now);

    return Positioned(
      top: 8,
      left: 8,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(4),
        ),
        child: DefaultTextStyle(
          style: const TextStyle(
            color: Colors.greenAccent,
            fontFamily: 'monospace',
            fontSize: 11,
            height: 1.4,
          ),
          child: stats.isEmpty
              ? const Text('Perf HUD: no data')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final s in stats) _PerfLine(stats: s),
                    const Divider(color: Colors.white24, height: 8),
                    Text(
                      'frame→hint p50=${endToEnd.p50Ms.toStringAsFixed(0)}ms '
                      'p90=${endToEnd.p90Ms.toStringAsFixed(0)}ms',
                      style: TextStyle(
                        // Gate go/no-go: đỏ khi p90 ≥ 100ms (NFR-1)
                        color: endToEnd.p90Ms >= 100
                            ? Colors.redAccent
                            : Colors.greenAccent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _PerfLine extends StatelessWidget {
  const _PerfLine({required this.stats});

  final PerfStats stats;

  @override
  Widget build(BuildContext context) {
    return Text(
      '${stats.detector.padRight(12)} '
      '${stats.fps.toStringAsFixed(1).padLeft(5)}fps  '
      'p50=${stats.p50Ms.toStringAsFixed(0).padLeft(3)}ms  '
      'p90=${stats.p90Ms.toStringAsFixed(0).padLeft(3)}ms',
    );
  }
}
